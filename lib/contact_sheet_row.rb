# frozen_string_literal: true

require 'adwaita'

# ContactSheetRow displays a single field value on the contact sheet.
#
# Ported from upstream's data/ui/contacts-contact-sheet-row.blp: a leading
# icon, the value as the row title, the field type as the subtitle, and any
# number of trailing action buttons (send mail, open map, visit website).
#
class ContactSheetRow < Adwaita::ActionRow
  PLACEHOLDER = '—'

  def initialize(value, subtitle = nil, icon: nil)
    super()
    self.title = display_value(value)
    unless subtitle.to_s.empty?
      self.subtitle = subtitle.to_s
    end
    self.title_selectable = !blank?(value)
    if icon
      add_prefix(Gtk::Image.new(icon_name: icon))
    end
    if blank?(value)
      add_css_class('dim-label')
    end
  end

  # Returns self so callers can keep adding buttons in one expression.
  def add_button(icon_name, tooltip = nil, &action)
    tap do |row|
      Gtk::Button.new.tap do |button|
        button.icon_name = icon_name
        button.valign = :center
        if tooltip
          button.tooltip_text = tooltip
        end
        button.add_css_class('flat')
        button.signal_connect('clicked') { action.call }
        row.add_suffix(button)
      end
    end
  end

  private

  # An empty field still gets a row, per the "show all fields" rule — it just
  # renders as a dimmed placeholder instead of a blank line.
    def display_value(value) = blank?(value) ? PLACEHOLDER : value.to_s

    def blank?(value) = value.to_s.strip.empty?
end
