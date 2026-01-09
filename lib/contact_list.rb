# frozen_string_literal: true

require 'adwaita'

# ContactList displays the list of contacts in the sidebar.
#
class ContactList
  AVATAR_SIZE = 32

  def initialize(store)
    @store = store
  end

  def build
    container.tap do |c|
      c.child = list_view

      list_view.tap do |lv|
        lv.model = @store.selection_model
        lv.factory = list_factory
      end
    end
  end

  # Memoized widget methods with styles

  def container
    @container ||= Gtk::ScrolledWindow.new.tap do |c|
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

  def list_factory
    @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect('setup') do |_, item|
        item.child = Gtk::Box.new(:horizontal, 12).tap do |box|
          box.margin_top = 8
          box.margin_bottom = 8
          box.margin_start = 12
          box.margin_end = 12

          box.append(Adwaita::Avatar.new(AVATAR_SIZE, nil, true))
          box.append(Gtk::Label.new.tap do |l|
            l.xalign = 0
            l.hexpand = true
            l.ellipsize = :end
          end)
        end
      end

      f.signal_connect('bind') do |_, item|
        item.item.then do |contact|
          item.child.tap do |box|
            box.first_child.tap do |avatar|
              avatar.text = contact.display_name
              avatar.show_initials = true
            end
            box.first_child.next_sibling.tap do |label|
              label.label = contact.display_name
            end
          end
        end
      end
    end
  end
end
