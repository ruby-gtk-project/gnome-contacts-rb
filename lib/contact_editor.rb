# frozen_string_literal: true

require 'adwaita'
require 'securerandom'

# ContactEditor is an in-place widget for editing contacts.
#
# Multi-value fields (emails, phones, etc.) always show one empty row at the end.
# When the user fills in the empty row, a new empty row appears.
#
class ContactEditor
  CONTACT_TYPES = [
    { id: 'personal', label: 'Personal' },
    { id: 'work', label: 'Work' },
    { id: 'home', label: 'Home' },
    { id: 'other', label: 'Other' }
  ].freeze

  def initialize(contact: nil)
    @contact = contact
    @is_new = contact.nil?

    # Track dynamic rows for multi-value fields
    @email_rows = []
    @phone_rows = []
    @url_rows = []
    @address_rows = []
    @note_rows = []
    @role_rows = []
  end

  def build
    container.tap do |c|
      c.append(avatar_section)
      c.append(name_group)
      c.append(emails_group)
      c.append(phones_group)
      c.append(roles_group)
      c.append(urls_group)
      c.append(addresses_group)
      c.append(birthday_group)
      c.append(notes_group)

      avatar_section.tap do |section|
        section.append(avatar)
        avatar.tap do |av|
          av.text = @contact&.display_name || ''
          av.show_initials = true
        end
      end

      name_group.tap do |group|
        group.add(name_row)
        group.add(nickname_row)

        name_row.tap { |r| r.text = @contact&.name || '' }
        nickname_row.tap { |r| r.text = @contact&.nickname || '' }
      end

      # Initialize multi-value fields
      init_emails
      init_phones
      init_roles
      init_urls
      init_addresses
      init_birthday
      init_notes
    end
  end

  def collect_data
    {
      id: @contact&.id || SecureRandom.uuid,
      name: name_row.text,
      nickname: nickname_row.text,
      birthday: parse_birthday(birthday_row.text),
      emails: collect_typed_values(@email_rows),
      phones: collect_typed_values(@phone_rows),
      urls: collect_typed_values(@url_rows),
      addresses: collect_typed_values(@address_rows),
      notes: collect_typed_values(@note_rows),
      roles: collect_roles
    }
  end

  # Memoized widget methods with styles

  def container
    @container ||= Gtk::Box.new(:vertical, 24).tap do |c|
      c.margin_top = 24
      c.margin_bottom = 24
      c.margin_start = 12
      c.margin_end = 12
    end
  end

  def avatar_section
    @avatar_section ||= Gtk::Box.new(:vertical, 12).tap do |section|
      section.halign = :center
    end
  end

  def avatar
    @avatar ||= Adwaita::Avatar.new(96, nil, true)
  end

  def name_group
    @name_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Name'
    end
  end

  def name_row
    @name_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Full Name'
      row.add_prefix(Gtk::Image.new(icon_name: 'avatar-default-symbolic'))
      row.signal_connect('changed') { update_avatar_from_name }
    end
  end

  def nickname_row
    @nickname_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Nickname'
      row.add_prefix(Gtk::Image.new(icon_name: 'avatar-default-symbolic'))
    end
  end

  def emails_group
    @emails_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Email'
    end
  end

  def phones_group
    @phones_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Phone'
    end
  end

  def roles_group
    @roles_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Organization'
    end
  end

  def urls_group
    @urls_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Website'
    end
  end

  def addresses_group
    @addresses_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Address'
    end
  end

  def birthday_group
    @birthday_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Birthday'
    end
  end

  def birthday_row
    @birthday_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Birthday'
      row.add_prefix(Gtk::Image.new(icon_name: 'birthday-symbolic'))
    end
  end

  def notes_group
    @notes_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Notes'
    end
  end

  private

  # Multi-value field initialization

  def init_emails
    (@contact&.emails || []).each { |email| add_email_row(email.value, email.type) }
    add_email_row('', 'personal') # Empty row for adding new
  end

  def init_phones
    (@contact&.phones || []).each { |phone| add_phone_row(phone.value, phone.type) }
    add_phone_row('', 'personal')
  end

  def init_roles
    (@contact&.roles || []).each { |role| add_role_row(role.organization, role.title, role.type) }
    add_role_row('', '', 'work')
  end

  def init_urls
    (@contact&.urls || []).each { |url| add_url_row(url.value, url.type) }
    add_url_row('', 'personal')
  end

  def init_addresses
    (@contact&.addresses || []).each { |addr| add_address_row(addr.value, addr.type) }
    add_address_row('', 'home')
  end

  def init_birthday
    birthday_group.add(birthday_row)
    birthday_row.text = format_birthday(@contact&.birthday)
  end

  def init_notes
    (@contact&.notes || []).each { |note| add_note_row(note.value) }
    add_note_row('')
  end

  # Row creation methods

  def add_email_row(value, type)
    create_typed_row(
      group: emails_group,
      rows: @email_rows,
      value: value,
      type: type,
      title: 'Add email',
      icon: 'mail-unread-symbolic',
      input_purpose: :email
    ) { add_email_row('', 'personal') }
  end

  def add_phone_row(value, type)
    create_typed_row(
      group: phones_group,
      rows: @phone_rows,
      value: value,
      type: type,
      title: 'Add phone number',
      icon: 'phone-symbolic',
      input_purpose: :phone
    ) { add_phone_row('', 'personal') }
  end

  def add_url_row(value, type)
    create_typed_row(
      group: urls_group,
      rows: @url_rows,
      value: value,
      type: type,
      title: 'Website',
      icon: 'web-browser-symbolic',
      input_purpose: :url
    ) { add_url_row('', 'personal') }
  end

  def add_address_row(value, type)
    create_typed_row(
      group: addresses_group,
      rows: @address_rows,
      value: value,
      type: type,
      title: 'Address',
      icon: 'mark-location-symbolic',
      input_purpose: :free_form
    ) { add_address_row('', 'home') }
  end

  def add_role_row(organization, title, type)
    row_data = { organization_row: nil, title_row: nil, type: type, added_new: false }

    # Organization row
    Adwaita::EntryRow.new.tap do |row|
      row.title = 'Organization'
      row.text = organization
      row.add_prefix(Gtk::Image.new(icon_name: 'building-symbolic'))
      row_data[:organization_row] = row

      row.signal_connect('changed') do
        ensure_empty_row_exists(row_data, @role_rows) { add_role_row('', '', 'work') }
      end

      roles_group.add(row)
    end

    # Title/Role row
    Adwaita::EntryRow.new.tap do |row|
      row.title = 'Role'
      row.text = title
      row_data[:title_row] = row

      row.signal_connect('changed') do
        ensure_empty_row_exists(row_data, @role_rows) { add_role_row('', '', 'work') }
      end

      roles_group.add(row)
    end

    @role_rows << row_data
  end

  def add_note_row(value)
    row_data = { text_view: nil, added_new: false }

    Adwaita::PreferencesRow.new.tap do |row|
      row.activatable = false

      Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_top = 12
        box.margin_bottom = 12
        box.margin_start = 12
        box.margin_end = 12

        Gtk::Image.new.tap do |icon|
          icon.icon_name = 'notepad-symbolic'
          icon.valign = :start
          icon.add_css_class('dim-label')
          box.append(icon)
        end

        Gtk::ScrolledWindow.new.tap do |sw|
          sw.hscrollbar_policy = :never
          sw.min_content_height = 80
          sw.hexpand = true

          Gtk::TextView.new.tap do |tv|
            tv.wrap_mode = :word_char
            tv.buffer.text = value
            row_data[:text_view] = tv

            tv.buffer.signal_connect('changed') do
              ensure_empty_row_exists(row_data, @note_rows) { add_note_row('') }
            end

            sw.child = tv
          end

          box.append(sw)
        end

        row.child = box
      end

      notes_group.add(row)
    end

    @note_rows << row_data
  end

  # Helper to create a typed entry row with type dropdown and prefix icon
  def create_typed_row(group:, rows:, value:, type:, title:, icon:, input_purpose:, &on_new_row)
    row_data = { entry_row: nil, type: type, added_new: false }

    Adwaita::EntryRow.new.tap do |row|
      row.title = title
      row.text = value
      row.input_purpose = input_purpose
      row.add_prefix(Gtk::Image.new(icon_name: icon))
      row_data[:entry_row] = row

      # Type dropdown as suffix
      Gtk::DropDown.new.tap do |dropdown|
        dropdown.model = Gtk::StringList.new(CONTACT_TYPES.map { |t| t[:label] })
        dropdown.selected = CONTACT_TYPES.index { |t| t[:id] == type } || 0
        dropdown.valign = :center

        dropdown.signal_connect('notify::selected') do
          row_data[:type] = CONTACT_TYPES[dropdown.selected][:id]
        end

        row.add_suffix(dropdown)
      end

      row.signal_connect('changed') do
        ensure_empty_row_exists(row_data, rows, &on_new_row)
      end

      group.add(row)
    end

    rows << row_data
  end

  def ensure_empty_row_exists(row_data, rows)
    row_data[:added_new].then do |added|
      if !added && !row_empty?(row_data)
        # Check if there's already an empty row
        has_empty = rows.any? { |r| row_empty?(r) }
        if !has_empty
          row_data[:added_new] = true
          yield
        end
      end
    end
  end

  def row_empty?(row_data)
    if row_data[:entry_row]
      row_data[:entry_row].text.strip.empty?
    elsif row_data[:organization_row]
      row_data[:organization_row].text.strip.empty? && row_data[:title_row].text.strip.empty?
    elsif row_data[:text_view]
      row_data[:text_view].buffer.text.strip.empty?
    else
      true
    end
  end

  # Data collection

  def collect_typed_values(rows)
    rows.filter_map do |row_data|
      if row_data[:entry_row]
        value = row_data[:entry_row].text.strip
        value.empty? ? nil : { value: value, type: row_data[:type] }
      elsif row_data[:text_view]
        value = row_data[:text_view].buffer.text.strip
        value.empty? ? nil : { value: value, type: 'personal' }
      end
    end
  end

  def collect_roles
    @role_rows.filter_map do |row_data|
      org = row_data[:organization_row].text.strip
      title = row_data[:title_row].text.strip
      (org.empty? && title.empty?) ? nil : { organization: org, title: title, type: row_data[:type] }
    end
  end

  def update_avatar_from_name
    avatar.text = name_row.text
  end

  def format_birthday(birthday)
    birthday.then do |b|
      if b.is_a?(Date)
        b.iso8601
      elsif b.is_a?(String)
        b
      else
        ''
      end
    end || ''
  end

  def parse_birthday(text)
    text.to_s.strip.then do |t|
      t.empty? ? nil : (Date.parse(t) rescue t)
    end
  end
end
