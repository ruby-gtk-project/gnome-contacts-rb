# frozen_string_literal: true

require 'adwaita'
require_relative 'avatar_selector'

# EditableAvatar is the avatar shown in the editor, with a camera badge that
# opens the AvatarSelector.
#
# Ported from upstream's src/contacts-editable-avatar.vala and
# data/ui/contacts-editable-avatar.blp: an overlay of the avatar with a small
# circular button pinned to its bottom-right corner.
#
class EditableAvatar
  def initialize(size, on_selected)
    @size = size
    @on_selected = on_selected
    @contact = nil
  end

  def build
    overlay.tap do |o|
      o.child = avatar
      o.add_overlay(edit_button)

      edit_button.signal_connect('clicked') { open_selector }
    end
  end

  def update(contact)
    @contact = contact
    avatar.tap do |av|
      av.text = contact&.display_name.to_s
      av.show_initials = true
      av.custom_image = contact&.avatar&.texture
    end
  end

  def set_avatar(avatar_data)
    avatar.custom_image = avatar_data&.texture
  end

  def text=(value)
    avatar.text = value.to_s
  end

  # Memoized widget methods

  def overlay = @overlay ||= Gtk::Overlay.new

  def avatar
    @avatar ||= Adwaita::Avatar.new(@size, nil, true).tap do |av|
      av.halign = :center
      av.valign = :center
    end
  end

  def edit_button
    @edit_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'photo-camera-symbolic'
      btn.tooltip_text = 'Change Avatar'
      btn.halign = :end
      btn.valign = :end
      btn.add_css_class('circular')
      btn.add_css_class('osd')
    end
  end

  private

    def open_selector
      AvatarSelector.new(@contact, method(:on_selected)).tap do |selector|
        selector.build
        selector.present(overlay.root)
      end
    end

    def on_selected(avatar_data) = @on_selected.call(avatar_data)
end
