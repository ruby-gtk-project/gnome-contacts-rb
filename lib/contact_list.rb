# frozen_string_literal: true

require 'adwaita'

# ContactList displays the list of contacts in the sidebar.
#
# Ported from upstream's src/contacts-contact-list.vala. The rows come from the
# store's sorted, filtered selection model; the stack swaps in an empty state
# when the address book is empty or the search matches nothing.
#
class ContactList
  AVATAR_SIZE = 32

  def initialize(store, on_selection_changed: nil)
    @store = store
    @on_selection_changed = on_selection_changed
    @selection_mode = false
    @selection_bindings = {}
  end

  def selection_mode? = @selection_mode

  # Swaps the model between single and multiple selection. Upstream's main
  # window does the same thing when its selection-mode button is toggled: the
  # rows grow a checkbox and the bottom bar offers the bulk actions.
  def selection_mode=(enabled)
    @selection_mode = enabled
    unless enabled
      @store.unmark_all
    end
    if enabled
      list_view.model = @store.multi_selection_model
    else
      list_view.model = @store.selection_model
    end
    refresh
  end

  def build
    stack.tap do |s|
      s.add_named(scroller, 'list')
      s.add_named(empty_page, 'empty')
      s.add_named(no_results_page, 'no-results')

      scroller.tap do |c|
        c.child = list_view

        list_view.tap do |lv|
          lv.model = @store.selection_model
          lv.factory = list_factory
        end
      end

      @store.sorted_model.signal_connect('items-changed') { update_visible_page }
    end.tap { update_visible_page }
  end

  # Forces every visible row to rebind, which is how a change to the display
  # order (first name vs surname) reaches rows already on screen.
  #
  # Re-emitting items-changed is not enough: when a splice reorders the *same*
  # objects, Gtk::ListView moves the existing row widgets rather than binding
  # them again, so a label that depends on anything other than the item itself
  # never updates. Handing the list view a fresh factory rebuilds every row.
  def refresh
    @selection_bindings.clear
    @list_factory = nil
    list_view.factory = list_factory
    update_visible_page
  end

  # Shows the list, the "no contacts yet" page or the "no results" page,
  # depending on whether the address book or just the current search is empty.
  def update_visible_page
    if @store.n_visible.positive?
      stack.visible_child_name = 'list'
    elsif @store.empty?
      stack.visible_child_name = 'empty'
    else
      stack.visible_child_name = 'no-results'
    end
  end

  # Memoized widget methods

  def stack = @stack ||= Gtk::Stack.new

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |c|
      c.hscrollbar_policy = :never
      c.vexpand = true
      c.hexpand = true
    end
  end

  def list_view
    @list_view ||= Gtk::ListView.new.tap do |lv|
      lv.add_css_class('navigation-sidebar')
    end
  end

  def empty_page
    @empty_page ||= Adwaita::StatusPage.new.tap do |sp|
      sp.icon_name = 'avatar-default-symbolic'
      sp.title = 'No Contacts'
      sp.description = 'Add a contact to get started'
      sp.vexpand = true
    end
  end

  def no_results_page
    @no_results_page ||= Adwaita::StatusPage.new.tap do |sp|
      sp.icon_name = 'system-search-symbolic'
      sp.title = 'No Results Found'
      sp.description = 'Try a different search'
      sp.vexpand = true
    end
  end

  def list_factory
    @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect('setup') { |_, item| item.child = row_template }
      f.signal_connect('unbind') { |_, item| release_selection_binding(item) }

      f.signal_connect('bind') do |_, item|
        item.item.then do |contact|
          item.child.tap do |box|
            avatar_of(box).tap do |avatar|
              avatar.text = contact.display_name
              avatar.show_initials = true
            end

            checkbox_of(box).tap do |checkbox|
              checkbox.visible = @selection_mode
              bind_selection(item, checkbox)
            end

            labels_of(box).tap do |labels|
              if @store.sort_on_surname
                labels.first_child.label = contact.sort_name(on_surname: true)
              else
                labels.first_child.label = contact.display_name
              end
              labels.first_child.next_sibling.label = subtitle_for(contact)
            end

            avatar_of(box).custom_image = contact.avatar&.texture

            # The star always occupies its slot so rows never reflow; only the
            # glyph and its emphasis change.
            box.last_child.tap do |star|
              if contact.favorite?
                star.icon_name = 'starred-symbolic'
                star.tooltip_text = 'Favourite'
                star.opacity = 1.0
              else
                star.icon_name = 'non-starred-symbolic'
                star.tooltip_text = nil
                star.opacity = 0.25
              end
            end
          end
        end
      end
    end
  end

  private

  # Ties the checkbox to the row's selected state with a property binding.
  #
  # Setting `checkbox.active` from the bind handler alone is not enough:
  # selecting a row later does not rebind it, so the tick never appeared even
  # though the row highlighted and the count in the header went up. A binding
  # keeps following Gtk::ListItem's "selected" property afterwards.
    def bind_selection(item, checkbox)
      release_selection_binding(item)
      @selection_bindings[item.object_id] = item.bind_property(
        'selected',
        checkbox,
        'active',
        :sync_create,
      )
    end

    def release_selection_binding(item)
      @selection_bindings.delete(item.object_id)&.unbind
    end

  # A fresh widget tree per list row — the factory's setup signal fires once
  # per recycled row, so this cannot be memoized.
    def row_template
      Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_top = 6
        box.margin_bottom = 6
        box.margin_start = 12
        box.margin_end = 12

        box.append(
          Gtk::CheckButton.new.tap do |checkbox|
                    checkbox.valign = :center
                    checkbox.visible = false
                    checkbox.can_focus = false
                    # The row's own click drives selection; the checkbox only reflects it,
                    # so it must not steal the press.
                    checkbox.sensitive = false
                  end,
        )

        box.append(Adwaita::Avatar.new(AVATAR_SIZE, nil, true))

        box.append(
          Gtk::Box.new(:vertical, 0).tap do |labels|
                    labels.hexpand = true
                    labels.valign = :center

                    labels.append(
                      Gtk::Label.new.tap do |l|
                                  l.xalign = 0
                                  l.ellipsize = :end
                                end,
                    )

                    labels.append(
                      Gtk::Label.new.tap do |l|
                                  l.xalign = 0
                                  l.ellipsize = :end
                                  l.add_css_class('dim-label')
                                  l.add_css_class('caption')
                                end,
                    )
                  end,
        )

        box.append(
          Gtk::Image.new.tap do |star|
                    star.icon_name = 'non-starred-symbolic'
                    star.valign = :center
                  end,
        )
      end
    end

  # Row children, by position: checkbox, avatar, labels box, favourite star.
    def checkbox_of(box) = box.first_child
    def avatar_of(box) = box.first_child.next_sibling
    def labels_of(box) = box.first_child.next_sibling.next_sibling

  # Secondary line: whatever identifies the contact beyond their name.
    def subtitle_for(contact)
      [contact.role_display, contact.emails.first&.value, contact.phones.first&.value]
        .map(&:to_s).find { |value| !value.strip.empty? }.to_s
    end
end
