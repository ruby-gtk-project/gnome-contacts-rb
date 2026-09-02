# frozen_string_literal: true

require 'adwaita'

# LinkSuggestionGrid is the bar shown under the contact sheet asking whether
# the shown contact is the same person as another, similar one.
#
# A port of upstream's src/contacts-link-suggestion-grid.vala and
# data/ui/contacts-link-suggestion-grid.blp.
#
class LinkSuggestionGrid
  AVATAR_SIZE = 54

  def initialize(suggestion, on_accept, on_reject)
    @suggestion = suggestion
    @on_accept = on_accept
    @on_reject = on_reject
  end

  def build
    container.tap do |c|
      c.append(avatar_bin)
      c.append(labels_box)
      c.append(buttons_box)

      avatar_bin.tap do |bin|
        bin.child = avatar

        avatar.tap do |av|
          av.text = @suggestion.display_name
          av.show_initials = true
          av.custom_image = @suggestion.avatar&.texture
        end
      end

      labels_box.tap do |box|
        box.append(description_label)
        box.append(extra_info_label)

        description_label.label = "Is this the same person as #{@suggestion.display_name}?"
        extra_info_label.label = extra_description
      end

      buttons_box.tap do |box|
        box.append(reject_button)
        box.append(accept_button)

        reject_button.signal_connect('clicked') { @on_reject.call(@suggestion) }
        accept_button.signal_connect('clicked') { @on_accept.call(@suggestion) }
      end
    end
  end

  # Memoized widget methods

  def container
    @container ||= Gtk::Box.new(:horizontal, 12).tap do |c|
      c.add_css_class('card')
      c.margin_top = 6
      c.margin_bottom = 12
      c.margin_start = 12
      c.margin_end = 12
      c.hexpand = true
    end
  end

  def avatar_bin
    @avatar_bin ||= Adwaita::Bin.new.tap do |bin|
      bin.valign = :center
      bin.margin_start = 12
      bin.margin_top = 12
      bin.margin_bottom = 12
    end
  end

  def avatar = @avatar ||= Adwaita::Avatar.new(AVATAR_SIZE, nil, true)

  def labels_box
    @labels_box ||= Gtk::Box.new(:vertical, 2).tap do |box|
      box.hexpand = true
      box.valign = :center
    end
  end

  def description_label
    @description_label ||= Gtk::Label.new.tap do |l|
      l.xalign = 0
      l.wrap = true
      l.add_css_class('heading')
    end
  end

  def extra_info_label
    @extra_info_label ||= Gtk::Label.new.tap do |l|
      l.xalign = 0
      l.wrap = true
      l.add_css_class('dim-label')
      l.add_css_class('caption')
    end
  end

  def buttons_box
    @buttons_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.valign = :center
      box.margin_end = 12
    end
  end

  def reject_button
    @reject_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_No'
      btn.use_underline = true
      btn.add_css_class('flat')
    end
  end

  def accept_button
    @accept_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Yes'
      btn.use_underline = true
      btn.add_css_class('suggested-action')
    end
  end

  private

  # Upstream shows an email, then a phone number, then a role — whichever the
  # suggested contact has first — to help tell two similar people apart.
  def extra_description
    [@suggestion.emails.first&.value,
     @suggestion.phones.first&.value,
     @suggestion.role_display].map(&:to_s).find { |v| !v.strip.empty? }.to_s
  end
end
