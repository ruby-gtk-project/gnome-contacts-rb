# frozen_string_literal: true

require 'gtk4'

# ContactSheetGroup displays a titled group of ContactSheetRows.
#
# Mimics Adw.PreferencesGroup behavior using Gtk::Frame and Gtk::ListBox.
#
class ContactSheetGroup
  def initialize(title:, rows: [])
    @title = title
    @rows = rows
  end

  def build
    container.tap do |c|
      c.append(title_label) if @title && !@title.empty?
      c.append(frame)

      frame.tap do |f|
        f.child = list_box

        list_box.tap do |lb|
          @rows.each { |row| lb.append(row.build) }
        end
      end
    end
  end

  def add_row(row)
    @rows << row
    list_box.append(row.build) if @list_box
  end

  # Memoized widget methods with styles

  def container
    @container ||= Gtk::Box.new(:vertical, 8).tap do |c|
      c.margin_top = 12
      c.margin_bottom = 12
      c.margin_start = 24
      c.margin_end = 24
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |l|
      l.label = @title
      l.xalign = 0
      l.add_css_class('heading')
    end
  end

  def frame
    @frame ||= Gtk::Frame.new.tap do |f|
      f.add_css_class('boxed-list-separate')
    end
  end

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |lb|
      lb.selection_mode = :none
      lb.add_css_class('boxed-list')
    end
  end
end
