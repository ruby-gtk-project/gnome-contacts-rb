# frozen_string_literal: true

require 'adwaita'
require 'securerandom'
require_relative 'type_set'
require_relative 'im_service'
require_relative 'editable_avatar'

# ContactEditor is the in-place form for creating and editing a contact.
#
# Ported from upstream's src/contacts-contact-editor.vala. Multi-value fields
# always keep one blank row at the end; typing into it appends a new blank one,
# which is how upstream lets you add an arbitrary number of emails or phones
# without an explicit "add" button.
#
class ContactEditor
  AVATAR_SIZE = 96

  # Multi-value fields that are a value plus a TypeSet label.
  TYPED_FIELDS = {
    emails:    { title: 'Add email', icon: 'mail-unread-symbolic', purpose: :email },
    phones:    { title: 'Add phone number', icon: 'phone-symbolic', purpose: :phone },
    urls:      { title: 'Website', icon: 'web-browser-symbolic', purpose: :url },
    addresses: { title: 'Address', icon: 'mark-location-symbolic', purpose: :free_form },
  }.freeze

  def initialize(contact: nil, on_avatar_change: nil)
    @contact = contact
    @on_avatar_change = on_avatar_change
    @avatar_data = contact&.avatar

    # Row bookkeeping, one array per multi-value field.
    @rows = (TYPED_FIELDS.keys + %i[notes roles im_addresses]).to_h { |field| [field, []] }
  end

  def build
    container.tap do |c|
      c.append(avatar_section)
      c.append(name_group)
      c.append(emails_group)
      c.append(phones_group)
      c.append(roles_group)
      c.append(im_group)
      c.append(urls_group)
      c.append(addresses_group)
      c.append(birthday_group)
      c.append(notes_group)

      avatar_section.tap do |section|
        section.append(editable_avatar.build)
        editable_avatar.update(@contact)
      end

      name_group.tap do |group|
        group.add(name_row)
        group.add(prefixes_row)
        group.add(given_name_row)
        group.add(additional_name_row)
        group.add(family_name_row)
        group.add(suffixes_row)
        group.add(nickname_row)
        group.add(alias_row)

        name_row.text = @contact&.name.to_s
        nickname_row.text = @contact&.nickname.to_s
        alias_row.text = @contact&.alias_name.to_s
        structured_name_rows.each { |field, row| row.text = structured_name.public_send(field).to_s }
      end

      birthday_group.tap do |group|
        group.add(birthday_row)
        birthday_row.text = format_birthday(@contact&.birthday)
      end

      init_typed_fields
      init_roles
      init_im_addresses
      init_notes
    end
  end

  def collect_data
    {
      id:              @contact&.id || SecureRandom.uuid,
      name:            name_row.text,
      alias_name:      alias_row.text,
      nickname:        nickname_row.text,
      birthday:        parse_birthday(birthday_row.text),
      structured_name: collect_structured_name,
      avatar:          @avatar_data,
      roles:           collect_roles,
      im_addresses:    collect_im_addresses,
      notes:           collect_notes,
    }.merge(TYPED_FIELDS.keys.to_h { |field| [field, collect_typed_values(@rows[field])] })
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

  def avatar_section
    @avatar_section ||= Gtk::Box.new(:vertical, 12).tap do |section|
      section.halign = :center
    end
  end

  def editable_avatar = @editable_avatar ||= EditableAvatar.new(AVATAR_SIZE, method(:on_avatar_selected))

  def name_group = @name_group ||= titled_group('Name')
  def emails_group = @emails_group ||= titled_group('Email')
  def phones_group = @phones_group ||= titled_group('Phone')
  def roles_group = @roles_group ||= titled_group('Organisation')
  def im_group = @im_group ||= titled_group('Instant Messaging')
  def urls_group = @urls_group ||= titled_group('Website')
  def addresses_group = @addresses_group ||= titled_group('Address')
  def birthday_group = @birthday_group ||= titled_group('Birthday')
  def notes_group = @notes_group ||= titled_group('Notes')

  def name_row = @name_row ||= entry_row('Full Name', icon: 'avatar-default-symbolic') { update_avatar_text }
  def prefixes_row = @prefixes_row ||= entry_row('Title')
  def given_name_row = @given_name_row ||= entry_row('First Name')
  def additional_name_row = @additional_name_row ||= entry_row('Middle Name')
  def family_name_row = @family_name_row ||= entry_row('Last Name')
  def suffixes_row = @suffixes_row ||= entry_row('Suffix')
  def nickname_row = @nickname_row ||= entry_row('Nickname', icon: 'avatar-default-symbolic')
  def alias_row = @alias_row ||= entry_row('Alias', icon: 'avatar-default-symbolic')
  def birthday_row = @birthday_row ||= entry_row('Birthday (YYYY-MM-DD)', icon: 'birthday-symbolic')

  # The five N components, in the order the editor shows them.
  def structured_name_rows
    @structured_name_rows ||= {
      prefixes:   prefixes_row,
      given:      given_name_row,
      additional: additional_name_row,
      family:     family_name_row,
      suffixes:   suffixes_row,
    }
  end

  def group_for(field)
    {
      emails:    emails_group,
      phones:    phones_group,
      urls:      urls_group,
      addresses: addresses_group,
    }.fetch(field)
  end

  private

    def titled_group(title)
      Adwaita::PreferencesGroup.new.tap do |group|
        group.title = title
      end
    end

    def entry_row(title, icon: nil, &on_change)
      Adwaita::EntryRow.new.tap do |row|
        row.title = title
        if icon
          row.add_prefix(Gtk::Image.new(icon_name: icon))
        end
        if on_change
          row.signal_connect('changed') { on_change.call }
        end
      end
    end

    def structured_name = @contact&.structured_name || StructuredName.empty

  # --- Field initialisation ----------------------------------------------

    def init_typed_fields
      TYPED_FIELDS.each_key do |field|
        Array(@contact&.public_send(field)).each { |v| add_typed_row(field, v.value, v.type) }
        add_typed_row(field, '', TypeSet.for_field(field).default.display_name)
      end
    end

    def init_roles
      Array(@contact&.roles).each { |role| add_role_row(role.organization, role.title) }
      add_role_row('', '')
    end

    def init_im_addresses
      Array(@contact&.im_addresses).each { |im| add_im_row(im.value, im.service) }
      add_im_row('', 'jabber')
    end

    def init_notes
      Array(@contact&.notes).each { |note| add_note_row(note.value) }
      add_note_row('')
    end

  # --- Row builders -------------------------------------------------------

    def add_typed_row(field, value, type)
      TypeSet.for_field(field).then do |type_set|
        { entry_row: nil, type: type, added_new: false }.tap do |row_data|
          Adwaita::EntryRow.new.tap do |row|
            row.title = TYPED_FIELDS[field][:title]
            row.text = value
            row.input_purpose = TYPED_FIELDS[field][:purpose]
            row.add_prefix(Gtk::Image.new(icon_name: TYPED_FIELDS[field][:icon]))
            row_data[:entry_row] = row

            row.add_suffix(type_dropdown(type_set, row_data))
            row.signal_connect('changed') do
              ensure_trailing_blank_row(row_data, @rows[field]) do
                add_typed_row(field, '', type_set.default.display_name)
              end
            end

            group_for(field).add(row)
          end

          @rows[field] << row_data
        end
      end
    end

  # A dropdown over the field's TypeSet, whose last entry ("Other…") swaps in
  # an entry for a custom label — upstream's TypeDescriptor.custom.
    def type_dropdown(type_set, row_data)
      Gtk::DropDown.new.tap do |dropdown|
        dropdown.model = Gtk::StringList.new(labels_including(type_set, row_data[:type]))
        dropdown.valign = :center
        dropdown.selected = selected_index(type_set, row_data[:type])

        dropdown.signal_connect('notify::selected') do
          dropdown.model.get_string(dropdown.selected).then do |label|
            if label == TypeSet::OTHER_LABEL
              prompt_for_custom_label(type_set, row_data, dropdown)
            else
              row_data[:type] = label
            end
          end
        end
      end
    end

  # A custom label the contact already carries has to appear in the model, or
  # the dropdown could not show it.
    def labels_including(type_set, type)
      type_set.index_of(type) ? type_set.labels : type_set.descriptors.map(&:display_name) + [type, TypeSet::OTHER_LABEL]
    end

    def selected_index(type_set, type)
      type_set.index_of(type) || type_set.descriptors.length
    end

  # Shown when the user picks "Other…": a small dialog collecting the label.
    def prompt_for_custom_label(type_set, row_data, dropdown)
      Adwaita::AlertDialog.new('Custom Type', 'Enter a label for this field').tap do |dialog|
        custom_label_entry(row_data).tap do |entry|
          dialog.extra_child = entry
          dialog.add_response('cancel', '_Cancel')
          dialog.add_response('save', '_Save')
          dialog.default_response = 'save'
          dialog.set_response_appearance('save', Adwaita::ResponseAppearance::SUGGESTED)

          dialog.signal_connect('response') do |_, response|
            if response == 'save' && !entry.text.strip.empty?
              row_data[:type] = entry.text.strip
              apply_custom_label(type_set, dropdown, row_data)
            else
              dropdown.selected = selected_index(type_set, row_data[:type])
            end
          end

          dialog.present(dropdown.root)
        end
      end
    end

    def custom_label_entry(row_data)
      Gtk::Entry.new.tap do |entry|
        entry.text = row_data[:type].to_s
        entry.margin_start = 12
        entry.margin_end = 12
        entry.margin_top = 6
        entry.margin_bottom = 6
      end
    end

  # Puts the custom label into the dropdown's model so it is what the user sees.
    def apply_custom_label(type_set, dropdown, row_data)
      (type_set.descriptors.map(&:display_name) + [row_data[:type], TypeSet::OTHER_LABEL]).then do |labels|
        dropdown.model = Gtk::StringList.new(labels)
        dropdown.selected = labels.length - 2
      end
    end

    def add_role_row(organization, title)
      { organization_row: nil, title_row: nil, added_new: false }.tap do |row_data|
        row_data[:organization_row] = role_entry(
          'Organisation',
          organization,
          'building-symbolic',
          row_data,
        )
        row_data[:title_row] = role_entry(
          'Role',
          title,
          nil,
          row_data,
        )
        @rows[:roles] << row_data
      end
    end

    def role_entry(title, value, icon, row_data)
      Adwaita::EntryRow.new.tap do |row|
        row.title = title
        row.text = value
        if icon
          row.add_prefix(Gtk::Image.new(icon_name: icon))
        end
        row.signal_connect('changed') do
          ensure_trailing_blank_row(row_data, @rows[:roles]) { add_role_row('', '') }
        end
        roles_group.add(row)
      end
    end

    def add_im_row(value, service)
      { entry_row: nil, service: service, added_new: false }.tap do |row_data|
        Adwaita::EntryRow.new.tap do |row|
          row.title = 'Add IM address'
          row.text = value
          row.add_prefix(Gtk::Image.new(icon_name: 'chat-symbolic'))
          row_data[:entry_row] = row
          row.add_suffix(im_service_dropdown(row_data))

          row.signal_connect('changed') do
            ensure_trailing_blank_row(row_data, @rows[:im_addresses]) { add_im_row('', 'jabber') }
          end

          im_group.add(row)
        end

        @rows[:im_addresses] << row_data
      end
    end

    def im_service_dropdown(row_data)
      Gtk::DropDown.new.tap do |dropdown|
        ImService.identifiers.then do |ids|
          dropdown.model = Gtk::StringList.new(ids.map { |id| ImService.display_name(id) })
          dropdown.valign = :center
          dropdown.selected = ids.index(row_data[:service]) || 0
          dropdown.signal_connect('notify::selected') { row_data[:service] = ids[dropdown.selected] }
        end
      end
    end

    def add_note_row(value)
      { text_view: nil, added_new: false }.tap do |row_data|
        Adwaita::PreferencesRow.new.tap do |row|
          row.activatable = false
          row.child = note_box(value, row_data)
          notes_group.add(row)
        end

        @rows[:notes] << row_data
      end
    end

    def note_box(value, row_data)
      Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_top = 12
        box.margin_bottom = 12
        box.margin_start = 12
        box.margin_end = 12

        box.append(
          Gtk::Image.new.tap do |icon|
                  icon.icon_name = 'notepad-symbolic'
                  icon.valign = :start
                  icon.add_css_class('dim-label')
                end,
        )

        box.append(
          Gtk::ScrolledWindow.new.tap do |sw|
                  sw.hscrollbar_policy = :never
                  sw.min_content_height = 80
                  sw.hexpand = true
                  sw.child = note_view(value, row_data)
                end,
        )
      end
    end

    def note_view(value, row_data)
      Gtk::TextView.new.tap do |tv|
        tv.wrap_mode = :word_char
        tv.buffer.text = value
        row_data[:text_view] = tv
        tv.buffer.signal_connect('changed') do
          ensure_trailing_blank_row(row_data, @rows[:notes]) { add_note_row('') }
        end
      end
    end

  # --- Blank-row bookkeeping ---------------------------------------------

  # Each multi-value group keeps exactly one blank row at the end: as soon as
  # the user types into the blank row, a fresh blank one is appended below it.
    def ensure_trailing_blank_row(row_data, rows)
      row_data[:added_new].then do |added|
        if !added && !row_empty?(row_data) && rows.none? { |row| row_empty?(row) }
          row_data[:added_new] = true
          yield
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

  # --- Collection ---------------------------------------------------------

    def collect_typed_values(rows)
      rows.filter_map do |row_data|
        row_data[:entry_row].text.strip.then do |value|
          unless value.empty?
            { value: value, type: row_data[:type] }
          end
        end
      end
    end

    def collect_im_addresses
      @rows[:im_addresses].filter_map do |row_data|
        row_data[:entry_row].text.strip.then do |value|
          unless value.empty?
            { value: value, service: row_data[:service] }
          end
        end
      end
    end

    def collect_notes
      @rows[:notes].filter_map do |row_data|
        row_data[:text_view].buffer.text.strip.then do |value|
          unless value.empty?
            { value: value, type: 'Home' }
          end
        end
      end
    end

    def collect_roles
      @rows[:roles].filter_map do |row_data|
        [row_data[:organization_row].text.strip, row_data[:title_row].text.strip].then do |org, title|
          unless org.empty? && title.empty?
            { organization: org, title: title, type: 'Work' }
          end
        end
      end
    end

    def collect_structured_name
      structured_name_rows.to_h { |field, row| [field, row.text.strip] }
    end

  # --- Avatar -------------------------------------------------------------

    def on_avatar_selected(avatar)
      @avatar_data = avatar
      editable_avatar.set_avatar(avatar)
      @on_avatar_change&.call(avatar)
    end

    def update_avatar_text = editable_avatar.text = name_row.text

    def format_birthday(birthday)
      case birthday
      when Date then birthday.iso8601
      when String then birthday
      else ''
      end
    end

    def parse_birthday(text)
      text.to_s.strip.then do |t|
        if t.empty?
          nil
        else
          begin
            Date.parse(t)
          rescue Date::Error
            t
          end
        end
      end
    end
end
