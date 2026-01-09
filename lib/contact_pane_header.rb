# frozen_string_literal: true

require 'gtk4'

# ContactPaneHeader displays the avatar and name at the top of the contact pane.
#
class ContactPaneHeader
  AVATAR_SIZE = 96

  def build
    container.tap do |c|
      c.append(avatar_frame)
      c.append(name_label)

      avatar_frame.tap do |af|
        af.child = avatar_label
      end
    end
  end

  def update(contact)
    name_label.label = contact.display_name
    avatar_label.label = contact.initials
  end

  def container
    @container ||= Gtk::Box.new(:vertical, 12).tap do |c|
      c.margin_top = 24
      c.margin_bottom = 24
      c.margin_start = 24
      c.margin_end = 24
    end
  end

  def avatar_frame
    @avatar_frame ||= Gtk::Frame.new.tap do |af|
      af.halign = :center
      af.add_css_class('circular')
    end
  end

  def avatar_label
    @avatar_label ||= Gtk::Label.new.tap do |l|
      l.set_size_request(AVATAR_SIZE, AVATAR_SIZE)
      l.add_css_class('title-1')
    end
  end

  def name_label
    @name_label ||= Gtk::Label.new.tap do |l|
      l.add_css_class('title-1')
      l.halign = :center
      l.wrap = true
      l.max_width_chars = 30
    end
  end
end
