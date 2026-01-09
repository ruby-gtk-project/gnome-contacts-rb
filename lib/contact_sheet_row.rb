# frozen_string_literal: true

require 'gtk4'

# ContactSheetRow displays a single field value in a ListBoxRow.
#
# Simple: icon, labels (subtitle + value), optional action button.
#
class ContactSheetRow
  def initialize(icon_name:, value:, subtitle: nil, on_action: nil, action_icon: nil, action_tooltip: nil)
    @icon_name = icon_name
    @value = value
    @subtitle = subtitle
    @on_action = on_action
    @action_icon = action_icon
    @action_tooltip = action_tooltip
  end

  def build
    row.tap do |r|
      r.child = content_box

      content_box.tap do |cb|
        cb.append(icon)
        cb.append(labels_box)

        labels_box.tap do |lb|
          lb.append(subtitle_label) if @subtitle
          lb.append(value_label)
        end

        @on_action.then do |handler|
          if handler
            cb.append(action_button)

            action_button.tap do |btn|
              btn.signal_connect('clicked') { handler.call(@value) }
            end
          end
        end
      end
    end
  end

  # Memoized widget methods with styles

  def row
    @row ||= Gtk::ListBoxRow.new.tap do |r|
      r.activatable = false
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:horizontal, 12).tap do |cb|
      cb.margin_top = 12
      cb.margin_bottom = 12
      cb.margin_start = 12
      cb.margin_end = 12
    end
  end

  def icon
    @icon ||= Gtk::Image.new.tap do |i|
      i.icon_name = @icon_name
      i.valign = :center
      i.add_css_class('dim-label')
    end
  end

  def labels_box
    @labels_box ||= Gtk::Box.new(:vertical, 2).tap do |lb|
      lb.hexpand = true
      lb.valign = :center
    end
  end

  def subtitle_label
    @subtitle_label ||= Gtk::Label.new.tap do |l|
      l.label = @subtitle.to_s
      l.xalign = 0
      l.add_css_class('dim-label')
      l.add_css_class('caption')
    end
  end

  def value_label
    @value_label ||= Gtk::Label.new.tap do |l|
      l.label = @value.to_s
      l.xalign = 0
      l.selectable = true
      l.wrap = true
    end
  end

  def action_button
    @action_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = @action_icon || 'go-next-symbolic'
      btn.tooltip_text = @action_tooltip
      btn.valign = :center
      btn.add_css_class('flat')
      btn.add_css_class('circular')
    end
  end
end
