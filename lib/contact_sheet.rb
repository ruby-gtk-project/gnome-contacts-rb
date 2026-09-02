# frozen_string_literal: true

require 'adwaita'
require 'uri'
require_relative 'contact_sheet_row'
require_relative 'im_service'

# ContactSheet displays the stored information of a single contact.
#
# Ported from upstream's src/contacts-contact-sheet.vala. Every field group is
# always present: a contact with no phone number still gets a Phone group with
# a placeholder row, so the sheet never reflows as you move between contacts.
#
class ContactSheet
  PROFILE_SIZE = 128

  # field => [group title, icon, row-builder]
  def initialize(contact)
    @contact = contact
  end

  def build
    container.tap do |c|
      c.append(header)
      c.append(roles_group)
      c.append(emails_group)
      c.append(phones_group)
      c.append(im_group)
      c.append(urls_group)
      c.append(addresses_group)
      c.append(birthday_group)
      c.append(nickname_group)
      c.append(notes_group)

      header.tap do |h|
        h.append(avatar)
        h.append(name_label)
        h.append(role_label)

        avatar.tap do |av|
          av.text = @contact.display_name
          av.show_initials = true
          av.custom_image = @contact.avatar&.texture
        end

        name_label.label = @contact.display_name
        role_label.label = @contact.role_display
      end

      roles_group.tap do |group|
        rows_for(@contact.roles, icon: 'building-symbolic') do |role|
          ContactSheetRow.new(role.display, role.type, icon: 'building-symbolic')
        end.each { |row| group.add(row) }
      end

      emails_group.tap do |group|
        rows_for(@contact.emails, icon: 'mail-unread-symbolic') do |email|
          ContactSheetRow.new(email.value, email.type, icon: 'mail-unread-symbolic')
                         .add_button('mail-send-symbolic', "Send email to #{email.value}") do
                           open_uri("mailto:#{email.value}")
                         end
        end.each { |row| group.add(row) }
      end

      phones_group.tap do |group|
        rows_for(@contact.phones, icon: 'phone-symbolic') do |phone|
          ContactSheetRow.new(phone.value, phone.type, icon: 'phone-symbolic')
                         .add_button('chat-symbolic', "Call #{phone.value}") do
                           open_uri("tel:#{phone.value.gsub(/[^+0-9]/, '')}")
                         end
        end.each { |row| group.add(row) }
      end

      im_group.tap do |group|
        rows_for(@contact.im_addresses, icon: 'chat-symbolic') do |im|
          ContactSheetRow.new(im.value, im.service_display_name, icon: 'chat-symbolic')
        end.each { |row| group.add(row) }
      end

      urls_group.tap do |group|
        rows_for(@contact.urls, icon: 'web-browser-symbolic') do |url|
          ContactSheetRow.new(url.value, url.type, icon: 'web-browser-symbolic')
                         .add_button('external-link-symbolic', 'Visit website') do
                           open_uri(absolute_url(url.value))
                         end
        end.each { |row| group.add(row) }
      end

      addresses_group.tap do |group|
        rows_for(@contact.addresses, icon: 'mark-location-symbolic') do |address|
          ContactSheetRow.new(address.value, address.type, icon: 'mark-location-symbolic')
                         .add_button('map-symbolic', 'Show on the map') do
                           open_uri("https://www.openstreetmap.org/search?query=#{URI.encode_www_form_component(address.value)}")
                         end
        end.each { |row| group.add(row) }
      end

      birthday_group.add(birthday_row)
      nickname_group.add(nickname_row)

      notes_group.tap do |group|
        rows_for(@contact.notes, icon: 'notepad-symbolic') do |note|
          ContactSheetRow.new(note.value, nil, icon: 'notepad-symbolic')
        end.each { |row| group.add(row) }
      end
    end
  end

  # Memoized widget methods

  def container
    @container ||= Gtk::Box.new(:vertical, 18).tap do |c|
      c.margin_top = 24
      c.margin_bottom = 24
      c.margin_start = 12
      c.margin_end = 12
    end
  end

  def header
    @header ||= Gtk::Box.new(:vertical, 6).tap do |h|
      h.halign = :center
      h.margin_top = 12
      h.margin_bottom = 12
    end
  end

  def avatar = @avatar ||= Adwaita::Avatar.new(PROFILE_SIZE, nil, true)

  def name_label
    @name_label ||= Gtk::Label.new.tap do |l|
      l.wrap = true
      l.wrap_mode = :word_char
      l.lines = 4
      l.justify = :center
      l.selectable = true
      l.add_css_class('title-1')
    end
  end

  def role_label
    @role_label ||= Gtk::Label.new.tap do |l|
      l.wrap = true
      l.justify = :center
      l.add_css_class('dim-label')
    end
  end

  def roles_group = @roles_group ||= titled_group('Organisation')
  def emails_group = @emails_group ||= titled_group('Email')
  def phones_group = @phones_group ||= titled_group('Phone')
  def im_group = @im_group ||= titled_group('Instant Messaging')
  def urls_group = @urls_group ||= titled_group('Website')
  def addresses_group = @addresses_group ||= titled_group('Address')
  def birthday_group = @birthday_group ||= titled_group('Birthday')
  def nickname_group = @nickname_group ||= titled_group('Nickname')
  def notes_group = @notes_group ||= titled_group('Notes')

  def birthday_row
    @birthday_row ||= ContactSheetRow.new(@contact.birthday_display, birthday_subtitle, icon: 'birthday-symbolic')
  end

  def nickname_row
    @nickname_row ||= ContactSheetRow.new(@contact.nickname, nil, icon: 'avatar-default-symbolic')
  end

  private

  def titled_group(title)
    Adwaita::PreferencesGroup.new.tap do |group|
      group.title = title
    end
  end

  # Builds one row per stored value, or a single placeholder row when the
  # contact has none — the sheet always shows every field.
  def rows_for(values, icon:, &row_builder)
    values.reject(&:empty?).then do |present|
      present.empty? ? [ContactSheetRow.new(nil, nil, icon: icon)] : present.map(&row_builder)
    end
  end

  def birthday_subtitle = @contact.birthday_today? ? 'Their birthday is today! 🎉' : nil

  def open_uri(uri)
    Gtk::UriLauncher.new(uri).launch(nil, nil) do |launcher, result|
      launcher.launch_finish(result)
    rescue GLib::Error => e
      warn "Could not open URI #{uri}: #{e.message}"
    end
  end

  def absolute_url(url) = url.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? url : "https://#{url}"
end
