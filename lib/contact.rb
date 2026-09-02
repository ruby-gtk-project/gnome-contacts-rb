# frozen_string_literal: true

require 'gtk4'
require 'date'
require 'base64'
require_relative 'type_set'
require_relative 'im_service'

# TypedValue is a value carrying a type label ("Work", "Home", "Mobile", or a
# custom label the user typed).
#
# Upstream models these as Chunk subclasses so Folks always sees valid data
# mid-edit; with plain file backends a two-field Data is enough.
TypedValue = Data.define(:value, :type)

# Reopened rather than configured in a Data.define block: constants assigned
# inside that block bind to the enclosing lexical scope (Object), so
# TypedValue::DEFAULT_TYPE would not exist.
class TypedValue
  DEFAULT_TYPE = 'Home'

  # Older releases of this port stored lower-case type ids rather than the
  # display labels upstream's TypeSet uses. Map them forward on read.
  LEGACY_TYPES = {
    'personal' => 'Personal',
    'work'     => 'Work',
    'home'     => 'Home',
    'other'    => 'Other',
  }.freeze

  def self.from_h(hash)
    new(
      value: hash[:value] || hash['value'] || '',
      type:  normalize_type(hash[:type] || hash['type']),
    )
  end

  def self.normalize_type(type)
    type.to_s.strip.then { |t| t.empty? ? DEFAULT_TYPE : LEGACY_TYPES.fetch(t, t) }
  end

  # Coerces anything the backends or the editor hand us into a TypedValue.
  # Already-typed values pass straight through, which is what keeps repeated
  # normalisation from wrapping a TypedValue inside another TypedValue.
  def self.coerce(value, default_type: DEFAULT_TYPE)
    case value
    when TypedValue then value
    when Hash then from_h(value)
    else new(value: value.to_s, type: default_type)
    end
  end

  def to_h = { value: value, type: type }
  def empty? = value.to_s.strip.empty?
end

# ImAddress is an instant-messaging address plus the service it belongs to.
# Ported from upstream's core/contacts-im-addresses-chunk.vala.
ImAddress = Data.define(:value, :service) do
  def self.from_h(hash)
    new(
      value:   hash[:value] || hash['value'] || '',
      service: (hash[:service] || hash['service'] || 'jabber').to_s,
    )
  end

  def self.coerce(value)
    case value
    when ImAddress then value
    when Hash then from_h(value)
    else new(value: value.to_s, service: 'jabber')
    end
  end

  def to_h = { value: value, service: service }
  def empty? = value.to_s.strip.empty?
  def service_display_name = ImService.display_name(service)
end

# Role represents an organisation plus a job title.
Role = Data.define(:organization, :title, :type) do
  def self.from_h(hash)
    new(
      organization: hash[:organization] || hash['organization'] || '',
      title:        hash[:title] || hash['title'] || '',
      type:         TypedValue.normalize_type(hash[:type] || hash['type'] || 'Work'),
    )
  end

  def self.coerce(value)
    case value
    when Role then value
    when Hash then from_h(value)
    else new(organization: value.to_s, title: '', type: 'Work')
    end
  end

  def to_h = { organization: organization, title: title, type: type }
  def empty? = organization.to_s.strip.empty? && title.to_s.strip.empty?

  def display
    [title, organization].map { |v| v.to_s.strip }.reject(&:empty?).join(' at ')
  end
end

# StructuredName is a full name split into its constituent parts.
# Ported from upstream's core/contacts-structured-name-chunk.vala, which wraps
# Folks.StructuredName; the field order matches vCard's N property.
StructuredName = Data.define(
  :family,
  :given,
  :additional,
  :prefixes,
  :suffixes,
)

# Reopened so FIELDS is StructuredName::FIELDS (see TypedValue above).
class StructuredName
  FIELDS = %i[family given additional prefixes suffixes].freeze

  def self.empty = new(family: '', given: '', additional: '', prefixes: '', suffixes: '')

  def self.from_h(hash)
    new(**FIELDS.to_h { |f| [f, (hash[f] || hash[f.to_s] || '').to_s] })
  end

  def self.coerce(value)
    case value
    when StructuredName then value
    when Hash then from_h(value)
    when nil then empty
    else from_full_name(value.to_s)
    end
  end

  # Best-effort split of a free-form name, used when importing a card that has
  # FN but no N.
  def self.from_full_name(name)
    name.to_s.strip.split(/\s+/).then do |parts|
      case parts.length
      when 0 then empty
      when 1 then empty.with(given: parts.first)
      else empty.with(
        given:      parts.first,
        family:     parts.last,
        additional: parts[1..-2].join(' '),
      )
      end
    end
  end

  def to_h = FIELDS.to_h { |f| [f, public_send(f)] }
  def empty? = FIELDS.all? { |f| public_send(f).to_s.strip.empty? }

  # Upstream renders "Prefix Given Additional Family, Suffix".
  def to_s
    [prefixes, given, additional, family].map { |p| p.to_s.strip }.reject(&:empty?).join(' ').then do |base|
      suffixes.to_s.strip.empty? ? base : [base, suffixes.to_s.strip].reject(&:empty?).join(', ')
    end
  end

  # "Family, Given" — what the sidebar shows when sorting on surname.
  def to_surname_first_s
    [family, given].map { |p| p.to_s.strip }.reject(&:empty?).then do |parts|
      parts.length > 1 ? "#{parts.first}, #{parts.last}" : parts.join
    end
  end
end

# Avatar holds a contact's photo as raw image bytes plus its media type.
# Upstream keeps a GLoadableIcon on an AvatarChunk; here the bytes travel with
# the contact so both file backends can persist them.
Avatar = Data.define(:data, :media_type)

# Reopened so STORED_SIZE is Avatar::STORED_SIZE (see TypedValue above).
class Avatar
  # Avatars are normalised to this many pixels square before being stored, so
  # a contact file never carries a multi-megabyte photograph.
  STORED_SIZE = 256

  def self.from_h(hash)
    (hash[:data] || hash['data']).then do |encoded|
      encoded.to_s.empty? ? nil : new(data: decode(encoded), media_type: hash[:media_type] || hash['media_type'] || 'image/png')
    end
  end

  def self.decode(value) = value.is_a?(String) ? Base64.decode64(value) : value.to_s

  def self.coerce(value)
    case value
    when Avatar, nil then value
    when Hash then from_h(value)
    else new(data: value.to_s, media_type: 'image/png')
    end
  end

  def to_h = { data: Base64.strict_encode64(data), media_type: media_type }
  def empty? = data.to_s.empty?

  # Gdk::Texture.new accepts a GLib::Bytes of encoded image data directly;
  # there is no new_from_bytes in these bindings.
  def texture
    Gdk::Texture.new(GLib::Bytes.new(data))
  rescue StandardError, GLib::Error => e
    warn "Could not decode avatar: #{e.message}"
    nil
  end

  def pixbuf
    GdkPixbuf::PixbufLoader.new.then do |loader|
      loader.write(data)
      loader.close
      loader.pixbuf
    end
  rescue StandardError, GLib::Error => e
    warn "Could not decode avatar: #{e.message}"
    nil
  end
end

# Contact represents a single contact entry.
#
# Ported from upstream's src/core/contacts-contact.vala. Upstream splits every
# field into a Chunk subclass so that Folks can be handed partial edits; the
# fields below are the same set (alias, avatar, birthday, email-addresses,
# im-addresses, full-name, structured-name, nickname, notes, phone-numbers,
# postal-addresses, roles, urls) held directly.
#
class Contact < GLib::Object
  type_register

  SINGLE_VALUE_FIELDS = %i[name alias_name nickname birthday favorite].freeze
  MULTI_VALUE_FIELDS = %i[emails phones urls addresses notes].freeze
  ALL_FIELDS = (SINGLE_VALUE_FIELDS + MULTI_VALUE_FIELDS + %i[roles im_addresses structured_name avatar]).freeze

  # Serialised as "alias" (upstream's name for it); spelled alias_name in Ruby
  # because `alias` is a keyword and cannot be a local variable or kwarg.
  attr_accessor :id, :name, :alias_name, :nickname, :birthday, :favorite
  attr_accessor :emails, :phones, :urls, :addresses, :notes, :roles, :im_addresses
  attr_accessor :structured_name, :avatar

  # Every contact the app knows about carries the id of the address book it
  # came from, so the preferences dialog can report where things live.
  attr_accessor :address_book

  def initialize(id:, name: '', alias_name: '', nickname: '', birthday: nil, favorite: false,
                 emails: [], phones: [], urls: [], addresses: [], notes: [], roles: [],
                 im_addresses: [], structured_name: nil, avatar: nil, address_book: nil)
    super()
    @id = id
    @name = name
    @alias_name = alias_name
    @nickname = nickname
    @birthday = birthday
    @favorite = favorite
    @emails = emails
    @phones = phones
    @urls = urls
    @addresses = addresses
    @notes = notes
    @roles = roles
    @im_addresses = im_addresses
    @structured_name = structured_name || StructuredName.empty
    @avatar = avatar
    @address_book = address_book
  end

  # Upstream's fetch_name: alias, then full name, then structured name, then
  # nickname — the first one that has anything in it.
  def fetch_name
    [@alias_name, @name, @structured_name&.to_s, @nickname]
      .map { |v| v.to_s.strip }.find { |v| !v.empty? }
  end

  # Upstream's fetch_display_name: a name if there is one, otherwise the first
  # email address, then the first phone number.
  def display_name
    [fetch_name, @emails.find { |e| !e.empty? }&.value, @phones.find { |p| !p.empty? }&.value]
      .map { |v| v.to_s.strip }.find { |v| !v.empty? } || 'Unnamed Contact'
  end

  # The name used for sorting and for the sidebar when "List Contacts By" is
  # set to Surname. Falls back to the display name when there is no surname.
  def sort_name(on_surname: false)
    @structured_name.then do |structured|
      if on_surname && structured && !structured.family.to_s.strip.empty?
        structured.to_surname_first_s
      else
        display_name
      end
    end
  end

  # First and last initial, which is what Adwaita::Avatar derives from a name.
  def initials
    display_name.split.then do |parts|
      parts.first(1).then do |first|
        if parts.length > 1
          first + [parts.last]
        else
          first
        end
      end.map { |part| part[0] }.join.upcase
    end
  end

  def role_display = @roles.find { |r| !r.empty? }&.display || ''

  def birthday_display
    @birthday.then do |bday|
      if bday.is_a?(Date)
        bday.strftime('%B %d, %Y')
      elsif bday.is_a?(String) && !bday.empty?
        bday
      end
    end
  end

  def birthday_today?
    @birthday.then do |bday|
      if bday.is_a?(Date)
        Date.today.then { |today| bday.month == today.month && bday.day == today.day }
      end
    end
  end

  def favorite? = @favorite == true
  def avatar? = !@avatar.nil? && !@avatar.empty?

  def to_h
    {
      id:              @id,
      name:            @name,
      alias:           @alias_name,
      nickname:        @nickname,
      birthday:        @birthday.is_a?(Date) ? @birthday.iso8601 : @birthday,
      favorite:        @favorite,
      structured_name: @structured_name&.to_h,
      avatar:          @avatar&.to_h,
      emails:          @emails.reject(&:empty?).map(&:to_h),
      phones:          @phones.reject(&:empty?).map(&:to_h),
      urls:            @urls.reject(&:empty?).map(&:to_h),
      addresses:       @addresses.reject(&:empty?).map(&:to_h),
      notes:           @notes.reject(&:empty?).map(&:to_h),
      roles:           @roles.reject(&:empty?).map(&:to_h),
      im_addresses:    @im_addresses.reject(&:empty?).map(&:to_h),
    }
  end

  def self.from_h(hash)
    new(
      id:              hash[:id] || hash['id'],
      name:            (hash[:name] || hash['name'] || '').to_s,
      # Accepts both spellings: "alias" is the serialised key (vCard/JSON),
      # "alias_name" is what Ruby callers pass because alias is a keyword.
      alias_name:      (hash[:alias_name] || hash['alias_name'] || hash[:alias] || hash['alias'] || '').to_s,
      nickname:        (hash[:nickname] || hash['nickname'] || '').to_s,
      birthday:        parse_birthday(hash[:birthday] || hash['birthday']),
      favorite:        hash[:favorite] || hash['favorite'] || false,
      structured_name: parse_structured_name(hash),
      avatar:          Avatar.coerce(hash[:avatar] || hash['avatar']),
      emails:          parse_multi_value(hash, :emails, :email),
      phones:          parse_multi_value(hash, :phones, :phone),
      urls:            parse_multi_value(hash, :urls, :url),
      addresses:       parse_multi_value(hash, :addresses, :address),
      notes:           parse_multi_value(hash, :notes, :notes),
      roles:           parse_roles(hash),
      im_addresses:    parse_im_addresses(hash),
      address_book:    hash[:address_book] || hash['address_book'],
    )
  end

  # Reads a multi-value field, accepting the single-string shape older
  # releases of this port wrote (email: "a@b.com" rather than emails: [...]).
  def self.parse_multi_value(hash, array_key, legacy_key)
    [hash[array_key] || hash[array_key.to_s],
     hash[legacy_key] || hash[legacy_key.to_s]
].then do |array_val, legacy_val|
      if array_val.is_a?(Array)
        array_val.map { |v| TypedValue.coerce(v) }
      elsif legacy_val.is_a?(String) && !legacy_val.strip.empty?
        [TypedValue.coerce(legacy_val)]
      else
        []
      end
    end
  end

  def self.parse_im_addresses(hash)
    (hash[:im_addresses] || hash['im_addresses']).then do |value|
      value.is_a?(Array) ? value.map { |v| ImAddress.coerce(v) } : []
    end
  end

  # A structured name is used as stored, and otherwise derived from the full
  # name so that sorting on surname works for contacts imported without an N.
  def self.parse_structured_name(hash)
    (hash[:structured_name] || hash['structured_name']).then do |value|
      StructuredName.coerce(value).then do |parsed|
        parsed.empty? ? StructuredName.from_full_name(hash[:name] || hash['name']) : parsed
      end
    end
  end

  def self.parse_roles(hash)
    (hash[:roles] || hash['roles']).then do |roles_val|
      if roles_val.is_a?(Array)
        roles_val.map { |v| Role.coerce(v) }
      else
        legacy_role(hash)
      end
    end
  end

  def self.legacy_role(hash)
    [hash[:organization] || hash['organization'], hash[:title] || hash['title']].map(&:to_s).then do |org, title|
      if org.strip.empty? && title.strip.empty?
        []
      else
        [Role.new(organization: org, title: title, type: 'Work')]
      end
    end
  end

  def self.parse_birthday(value)
    value.then do |v|
      if v.is_a?(Date)
        v
      elsif v.is_a?(String) && !v.empty?
        begin
          Date.parse(v)
        rescue Date::Error
          v
        end
      end
    end
  end

  def to_s = "#<Contact id=#{@id} name=#{display_name.inspect}>"
  def inspect = to_s
end
