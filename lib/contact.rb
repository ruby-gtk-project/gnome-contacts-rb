# frozen_string_literal: true

require 'gtk4'

# TypedValue represents a value with a type label (e.g., "Work", "Home", "Personal")
TypedValue = Data.define(:value, :type) do
  def self.from_h(hash)
    new(
      value: hash[:value] || hash['value'] || '',
      type: hash[:type] || hash['type'] || 'personal'
    )
  end

  def to_h
    { value: value, type: type }
  end

  def empty?
    value.to_s.strip.empty?
  end
end

# Role represents organization + title
Role = Data.define(:organization, :title, :type) do
  def self.from_h(hash)
    new(
      organization: hash[:organization] || hash['organization'] || '',
      title: hash[:title] || hash['title'] || '',
      type: hash[:type] || hash['type'] || 'work'
    )
  end

  def to_h
    { organization: organization, title: title, type: type }
  end

  def empty?
    organization.to_s.strip.empty? && title.to_s.strip.empty?
  end

  def display
    [title, organization].map { |v| v.to_s.strip }.reject(&:empty?).join(' at ')
  end
end

# Contact represents a single contact entry.
#
# Multi-value fields: emails, phones, urls, addresses, notes, roles
# Single-value fields: name, nickname, birthday
#
class Contact < GLib::Object
  type_register

  # Single-value fields
  attr_accessor :id, :name, :nickname, :birthday, :favorite

  # Multi-value fields (arrays of TypedValue or Role)
  attr_accessor :emails, :phones, :urls, :addresses, :notes, :roles

  # Type options for dropdowns
  CONTACT_TYPES = %w[personal work home other].freeze
  ADDRESS_TYPES = %w[home work other].freeze

  def initialize(
    id:,
    name: '',
    nickname: '',
    birthday: nil,
    favorite: false,
    emails: [],
    phones: [],
    urls: [],
    addresses: [],
    notes: [],
    roles: []
  )
    super()
    @id = id
    @name = name
    @nickname = nickname
    @birthday = birthday
    @favorite = favorite
    @emails = emails
    @phones = phones
    @urls = urls
    @addresses = addresses
    @notes = notes
    @roles = roles
  end

  def display_name
    primary_email = @emails.find { |e| !e.empty? }&.value
    primary_phone = @phones.find { |p| !p.empty? }&.value
    [@name, primary_email, primary_phone]
      .map { |v| v.to_s.strip }
      .find { |v| !v.empty? } || 'Unnamed Contact'
  end

  def initials
    display_name.split.map { |p| p[0] }.take(2).join.upcase
  end

  def role_display
    @roles.find { |r| !r.empty? }&.display || ''
  end

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
        today = Date.today
        bday.month == today.month && bday.day == today.day
      end
    end
  end

  def favorite?
    @favorite == true
  end

  def to_h
    {
      id: @id,
      name: @name,
      nickname: @nickname,
      birthday: @birthday.is_a?(Date) ? @birthday.iso8601 : @birthday,
      favorite: @favorite,
      emails: @emails.reject(&:empty?).map(&:to_h),
      phones: @phones.reject(&:empty?).map(&:to_h),
      urls: @urls.reject(&:empty?).map(&:to_h),
      addresses: @addresses.reject(&:empty?).map(&:to_h),
      notes: @notes.reject(&:empty?).map(&:to_h),
      roles: @roles.reject(&:empty?).map(&:to_h)
    }
  end

  def self.from_h(hash)
    birthday_val = hash[:birthday] || hash['birthday']
    birthday_parsed = parse_birthday(birthday_val)

    # Handle legacy single-value format
    emails = parse_multi_value(hash, :emails, :email)
    phones = parse_multi_value(hash, :phones, :phone)
    urls = parse_multi_value(hash, :urls, :url)
    addresses = parse_multi_value(hash, :addresses, :address)
    notes = parse_multi_value(hash, :notes, :notes)
    roles = parse_roles(hash)

    new(
      id: hash[:id] || hash['id'],
      name: hash[:name] || hash['name'] || '',
      nickname: hash[:nickname] || hash['nickname'] || '',
      birthday: birthday_parsed,
      favorite: hash[:favorite] || hash['favorite'] || false,
      emails: emails,
      phones: phones,
      urls: urls,
      addresses: addresses,
      notes: notes,
      roles: roles
    )
  end

  def self.parse_multi_value(hash, array_key, legacy_key)
    array_val = hash[array_key] || hash[array_key.to_s]
    legacy_val = hash[legacy_key] || hash[legacy_key.to_s]

    if array_val.is_a?(Array)
      array_val.map { |v| v.is_a?(Hash) ? TypedValue.from_h(v) : TypedValue.new(value: v.to_s, type: 'personal') }
    elsif legacy_val.is_a?(String) && !legacy_val.strip.empty?
      [TypedValue.new(value: legacy_val, type: 'personal')]
    else
      []
    end
  end

  def self.parse_roles(hash)
    roles_val = hash[:roles] || hash['roles']
    org_val = hash[:organization] || hash['organization']
    title_val = hash[:title] || hash['title']

    if roles_val.is_a?(Array)
      roles_val.map { |v| Role.from_h(v) }
    elsif (org_val.is_a?(String) && !org_val.strip.empty?) || (title_val.is_a?(String) && !title_val.strip.empty?)
      [Role.new(organization: org_val.to_s, title: title_val.to_s, type: 'work')]
    else
      []
    end
  end

  def self.parse_birthday(value)
    value.then do |v|
      if v.is_a?(Date)
        v
      elsif v.is_a?(String) && !v.empty?
        Date.parse(v) rescue v
      end
    end
  end

  def to_s = "#<Contact id=#{@id} name=#{@name.inspect}>"
  def inspect = to_s
end
