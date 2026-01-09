# frozen_string_literal: true

require 'adwaita'
require 'uri'

# ContactSheet displays the actual information of a contact.
#
class ContactSheet
  PROFILE_SIZE = 128

  def initialize(contact)
    @contact = contact
  end

  def build
    container.tap do |c|
      c.append(header)
      build_field_groups.each { |group| c.append(group) }

      header.tap do |h|
        h.append(avatar)
        h.append(name_label)

        avatar.tap do |av|
          av.text = @contact.display_name
          av.show_initials = true
        end

        name_label.tap do |l|
          l.label = @contact.display_name
        end
      end
    end
  end

  # Memoized widget methods

  def container
    @container ||= Gtk::Box.new(:vertical, 24).tap do |c|
      c.margin_top = 24
      c.margin_bottom = 24
      c.margin_start = 12
      c.margin_end = 12
    end
  end

  def header
    @header ||= Gtk::Box.new(:vertical, 0).tap do |h|
      h.halign = :center
      h.margin_top = 24
      h.margin_bottom = 24
    end
  end

  def avatar
    @avatar ||= Adwaita::Avatar.new(PROFILE_SIZE, nil, true)
  end

  def name_label
    @name_label ||= Gtk::Label.new.tap do |l|
      l.hexpand = true
      l.wrap = true
      l.wrap_mode = :word_char
      l.lines = 4
      l.width_chars = 10
      l.selectable = true
      l.add_css_class('title-1')
    end
  end

  private

  def build_field_groups
    [].tap do |groups|
      create_widget_for_roles.then { |g| groups << g if g }
      create_widget_for_emails.then { |g| groups << g if g }
      create_widget_for_phones.then { |g| groups << g if g }
      create_widget_for_urls.then { |g| groups << g if g }
      create_widget_for_addresses.then { |g| groups << g if g }
      create_widget_for_birthday.then { |g| groups << g if g }
      create_widget_for_nickname.then { |g| groups << g if g }
      create_widget_for_notes.then { |g| groups << g if g }
    end
  end

  def create_widget_for_roles
    non_empty_roles = @contact.roles.reject(&:empty?)
    non_empty_roles.empty?.then do |empty|
      if empty
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          non_empty_roles.each do |role|
            group.add(ContactSheetRow.new(role.display, type_label(role.type), icon: 'building-symbolic'))
          end
        end
      end
    end
  end

  def create_widget_for_emails
    non_empty = @contact.emails.reject(&:empty?)
    non_empty.empty?.then do |empty|
      if empty
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          non_empty.each do |email|
            ContactSheetRow.new(email.value, type_label(email.type), icon: 'mail-unread-symbolic').tap do |row|
              row.add_button('mail-send-symbolic', "Send email to #{email.value}") do
                open_uri("mailto:#{email.value}")
              end
              group.add(row)
            end
          end
        end
      end
    end
  end

  def create_widget_for_phones
    non_empty = @contact.phones.reject(&:empty?)
    non_empty.empty?.then do |empty|
      if empty
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          non_empty.each do |phone|
            group.add(ContactSheetRow.new(phone.value, type_label(phone.type), icon: 'phone-symbolic'))
          end
        end
      end
    end
  end

  def create_widget_for_urls
    non_empty = @contact.urls.reject(&:empty?)
    non_empty.empty?.then do |empty|
      if empty
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          non_empty.each do |url|
            ContactSheetRow.new(url.value, nil, icon: 'web-browser-symbolic').tap do |row|
              row.add_button('external-link-symbolic', 'Visit website') do
                open_uri(ensure_absolute_url(url.value))
              end
              group.add(row)
            end
          end
        end
      end
    end
  end

  def create_widget_for_addresses
    non_empty = @contact.addresses.reject(&:empty?)
    non_empty.empty?.then do |empty|
      if empty
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          non_empty.each do |address|
            ContactSheetRow.new(address.value, type_label(address.type), icon: 'mark-location-symbolic').tap do |row|
              row.add_button('map-symbolic', 'Show on the map') do
                open_uri("maps:q=#{URI.encode_www_form_component(address.value)}")
              end
              group.add(row)
            end
          end
        end
      end
    end
  end

  def create_widget_for_birthday
    @contact.birthday_display.then do |birthday|
      if birthday
        subtitle = @contact.birthday_today? ? 'Their birthday is today! 🎉' : nil
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          group.add(ContactSheetRow.new(birthday, subtitle, icon: 'birthday-symbolic'))
        end
      end
    end
  end

  def create_widget_for_nickname
    @contact.nickname.to_s.strip.then do |nickname|
      if nickname.empty?
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          group.add(ContactSheetRow.new(nickname, nil, icon: 'avatar-default-symbolic'))
        end
      end
    end
  end

  def create_widget_for_notes
    non_empty = @contact.notes.reject(&:empty?)
    non_empty.empty?.then do |empty|
      if empty
        nil
      else
        Adwaita::PreferencesGroup.new.tap do |group|
          group.add_css_class('boxed-list')
          non_empty.each do |note|
            group.add(ContactSheetRow.new(note.value, nil, icon: 'notepad-symbolic'))
          end
        end
      end
    end
  end

  def type_label(type)
    type&.capitalize
  end

  def open_uri(uri)
    Gtk::UriLauncher.new(uri).launch(nil, nil) do |launcher, result|
      launcher.launch_finish(result)
    rescue GLib::Error => e
      warn "Could not open URI #{uri}: #{e.message}"
    end
  end

  def ensure_absolute_url(url)
    url.match?(%r{^https?://}) ? url : "https://#{url}"
  end
end

# ContactSheetRow displays a single field value using Adwaita::ActionRow
#
class ContactSheetRow < Adwaita::ActionRow
  def initialize(title, subtitle = nil, icon: nil)
    super()
    self.title = title
    self.subtitle = subtitle if subtitle
    add_prefix(Gtk::Image.new(icon_name: icon)) if icon
  end

  def add_button(icon_name, tooltip = nil, &action)
    Gtk::Button.new.tap do |button|
      button.icon_name = icon_name
      button.valign = :center
      button.add_css_class('flat')
      button.tooltip_text = tooltip if tooltip
      button.signal_connect('clicked') { action.call }
      add_suffix(button)
    end
  end
end
