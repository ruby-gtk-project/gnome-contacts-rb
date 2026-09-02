# frozen_string_literal: true

require 'adwaita'
require_relative 'vcard'

# ImportDialog previews the contacts found in the chosen files and imports them
# on confirmation.
#
# Ported from upstream's src/contacts-import-dialog.vala and
# data/ui/contacts-import-dialog.blp: a group per file listing the contacts it
# contains, Cancel and Import in the header bar, and an error row for any file
# that could not be read.
#
class ImportDialog < Adwaita::Dialog
  def initialize(files, on_import)
    super()
    self.title = 'Import Contacts'
    self.content_width = 440
    self.content_height = 460
    @files = Array(files)
    @on_import = on_import
    @parsed = []
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |tv|
        tv.add_top_bar(header_bar)
        tv.content = page

        header_bar.tap do |hb|
          hb.show_start_title_buttons = false
          hb.show_end_title_buttons = false
          hb.pack_start(cancel_button)
          hb.pack_end(import_button)

          cancel_button.signal_connect('clicked') { close }
          import_button.signal_connect('clicked') { confirm }
        end

        page.tap do |p|
          @files.each { |file| p.add(group_for(file)) }
        end
      end

      import_button.sensitive = @parsed.any?
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new
  def page = @page ||= Adwaita::PreferencesPage.new

  def cancel_button
    @cancel_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Cancel'
      btn.use_underline = true
    end
  end

  def import_button
    @import_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Import'
      btn.use_underline = true
      btn.add_css_class('suggested-action')
    end
  end

  private

  # One group per file, titled with the file's display name — upstream only
  # shows the header when importing more than one file, but a single titled
  # group reads no worse and keeps the code simpler.
  def group_for(file)
    Adwaita::PreferencesGroup.new.tap do |group|
      group.title = display_name(file)

      parse(file).then do |contacts|
        if contacts.nil?
          group.add(error_row('An error occurred reading the selected file'))
        elsif contacts.empty?
          group.add(error_row('No contacts found in this file'))
        else
          @parsed.concat(contacts)
          group.description = summary(contacts.length)
          contacts.each { |contact| group.add(contact_row(contact)) }
        end
      end
    end
  end

  # nil means the file could not be read at all, which the dialog reports
  # differently from a file that simply held no contacts.
  def parse(file)
    VCard.parse_all(File.read(file.path))
  rescue StandardError => e
    warn "Could not read #{file.path}: #{e.message}"
    nil
  end

  def summary(count) = count == 1 ? '1 contact' : "#{count} contacts"

  # Adwaita row titles are Pango markup, and there is no GLib::Markup in these
  # bindings, so escape the special characters here.
  MARKUP_ESCAPES = { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;' }.freeze

  def contact_row(contact)
    Adwaita::ActionRow.new.tap do |row|
      row.title = escape(preview_name(contact))
      row.subtitle = escape(preview_detail(contact))
      row.add_prefix(Adwaita::Avatar.new(32, preview_name(contact), true))
    end
  end

  def escape(text) = text.to_s.gsub(/[&<>]/) { |char| MARKUP_ESCAPES.fetch(char) }

  def preview_name(contact)
    [contact[:name], contact[:nickname], contact[:alias]].map(&:to_s)
                                                         .find { |v| !v.strip.empty? } || 'Unnamed Contact'
  end

  def preview_detail(contact)
    [contact[:emails], contact[:phones]].flatten.compact.map { |v| v[:value] }
                                        .find { |v| !v.to_s.strip.empty? }.to_s
  end

  def error_row(message)
    Adwaita::ActionRow.new.tap do |row|
      row.title = message
      row.add_prefix(Gtk::Image.new(icon_name: 'dialog-warning-symbolic'))
      row.add_css_class('dim-label')
    end
  end

  def display_name(file)
    file.query_info(Gio::FileAttribute::STANDARD_DISPLAY_NAME, :none).display_name
  rescue StandardError, GLib::Error
    File.basename(file.path.to_s)
  end

  def confirm
    @on_import.call(@parsed)
    close
  end
end
