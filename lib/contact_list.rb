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

  def initialize(store)
    @store = store
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

  # Shows the list, the "no contacts yet" page or the "no results" page,
  # depending on whether the address book or just the current search is empty.
  def update_visible_page
    stack.visible_child_name =
      if @store.n_visible.positive?
        'list'
      elsif @store.empty?
        'empty'
      else
        'no-results'
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

      f.signal_connect('bind') do |_, item|
        item.item.then do |contact|
          item.child.tap do |box|
            box.first_child.tap do |avatar|
              avatar.text = contact.display_name
              avatar.show_initials = true
            end

            box.first_child.next_sibling.tap do |labels|
              labels.first_child.label = contact.display_name
              labels.first_child.next_sibling.label = subtitle_for(contact)
            end

            # The star always occupies its slot so rows never reflow; only the
            # glyph and its emphasis change.
            box.last_child.tap do |star|
              star.icon_name = contact.favorite? ? 'starred-symbolic' : 'non-starred-symbolic'
              star.tooltip_text = contact.favorite? ? 'Favourite' : nil
              star.opacity = contact.favorite? ? 1.0 : 0.25
            end
          end
        end
      end
    end
  end

  private

  # A fresh widget tree per list row — the factory's setup signal fires once
  # per recycled row, so this cannot be memoized.
  def row_template
    Gtk::Box.new(:horizontal, 12).tap do |box|
      box.margin_top = 6
      box.margin_bottom = 6
      box.margin_start = 12
      box.margin_end = 12

      box.append(Adwaita::Avatar.new(AVATAR_SIZE, nil, true))

      box.append(Gtk::Box.new(:vertical, 0).tap do |labels|
        labels.hexpand = true
        labels.valign = :center

        labels.append(Gtk::Label.new.tap do |l|
          l.xalign = 0
          l.ellipsize = :end
        end)

        labels.append(Gtk::Label.new.tap do |l|
          l.xalign = 0
          l.ellipsize = :end
          l.add_css_class('dim-label')
          l.add_css_class('caption')
        end)
      end)

      box.append(Gtk::Image.new.tap do |star|
        star.icon_name = 'non-starred-symbolic'
        star.valign = :center
      end)
    end
  end

  # Secondary line: whatever identifies the contact beyond their name.
  def subtitle_for(contact)
    [contact.role_display, contact.emails.first&.value, contact.phones.first&.value]
      .map(&:to_s).find { |value| !value.strip.empty? }.to_s
  end
end
