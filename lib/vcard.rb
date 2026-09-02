# frozen_string_literal: true

require 'date'
require 'securerandom'
require_relative 'contact'

# VCard serialises and parses contacts as vCard 4.0 (RFC 6350).
#
# This is the Ruby counterpart of upstream's src/io/contacts-io-vcard-parser.vala
# and src/io/contacts-io-vcard-export-operation.vala, collapsed into one module
# because both directions share the same escaping and property grammar.
#
# Everything here works on plain contact hashes (the shape Contact#to_h and
# Contact.from_h speak), so it is equally usable by VCardBackend and by the
# import/export menu actions.
#
module VCard
  MIME_TYPE = 'text/vcard'
  EOL = "\r\n"

  # vCard TYPE parameter <-> our own type labels.
  TYPE_TO_VCARD = { 'personal' => 'HOME', 'home' => 'HOME', 'work' => 'WORK', 'other' => 'OTHER' }.freeze
  VCARD_TO_TYPE = { 'HOME' => 'home', 'WORK' => 'work', 'OTHER' => 'other', 'CELL' => 'personal',
                    'VOICE' => 'personal', 'INTERNET' => 'personal', 'PREF' => 'personal' }.freeze

  module_function

  # --- Export -------------------------------------------------------------

  # Serialises one contact hash into a single VCARD block (no trailing EOL).
  def dump(contact)
    lines(contact).map { |line| fold(line) }.join(EOL)
  end

  # Serialises many contact hashes into one file's worth of text.
  def dump_all(contacts)
    "#{contacts.map { |contact| dump(contact) }.join(EOL)}#{EOL}"
  end

  def lines(contact)
    [].tap do |out|
      out << 'BEGIN:VCARD'
      out << 'VERSION:4.0'
      out << "UID:#{escape(contact[:id])}" if contact[:id]
      out << "FN:#{escape(contact[:name])}" unless blank?(contact[:name])
      out << "N:#{structured_name(contact[:name])}" unless blank?(contact[:name])
      out << "NICKNAME:#{escape(contact[:nickname])}" unless blank?(contact[:nickname])
      typed_lines(out, contact[:emails], 'EMAIL')
      typed_lines(out, contact[:phones], 'TEL')
      typed_lines(out, contact[:urls], 'URL')
      address_lines(out, contact[:addresses])
      role_lines(out, contact[:roles])
      out << "BDAY:#{format_birthday(contact[:birthday])}" unless blank?(format_birthday(contact[:birthday]))
      note_lines(out, contact[:notes])
      out << 'CATEGORIES:Favourite' if contact[:favorite]
      out << 'END:VCARD'
    end
  end

  def typed_lines(out, values, property)
    each_value(values) do |value, type|
      out << "#{property};TYPE=#{TYPE_TO_VCARD.fetch(type, 'OTHER')}:#{escape(value)}"
    end
  end

  def address_lines(out, values)
    each_value(values) do |value, type|
      # ADR is PO box; extended; street; locality; region; postcode; country.
      # We keep a free-form address, so it goes in the street component.
      out << "ADR;TYPE=#{TYPE_TO_VCARD.fetch(type, 'OTHER')}:;;#{escape(value)};;;;"
    end
  end

  def note_lines(out, values)
    each_value(values) { |value, _type| out << "NOTE:#{escape(value)}" }
  end

  def role_lines(out, roles)
    Array(roles).each do |role|
      to_role_hash(role).then do |data|
        out << "ORG:#{escape(data[:organization])}" unless blank?(data[:organization])
        out << "TITLE:#{escape(data[:title])}" unless blank?(data[:title])
      end
    end
  end

  def each_value(values)
    Array(values).each do |entry|
      to_typed_hash(entry).then do |data|
        yield(data[:value], data[:type]) unless blank?(data[:value])
      end
    end
  end

  # --- Import -------------------------------------------------------------

  # Parses a file's worth of vCard text into an array of contact hashes.
  def parse_all(text)
    split_cards(unfold(text.to_s)).map { |card| parse_card(card) }.compact
  end

  # Parses a single VCARD block into a contact hash, or nil if it holds nothing.
  def parse_card(lines)
    blank_contact.tap do |contact|
      lines.each { |line| apply_property(contact, line) }
      contact[:id] ||= SecureRandom.uuid
      pair_roles(contact)
    end.then { |contact| meaningful?(contact) ? contact : nil }
  end

  def apply_property(contact, line)
    parse_line(line).then do |name, params, value|
      case name
      when 'UID' then contact[:id] = unescape(value)
      when 'FN' then contact[:name] = unescape(value)
      when 'N' then contact[:name] = name_from_structured(value) if blank?(contact[:name])
      when 'NICKNAME' then contact[:nickname] = unescape(value).split(',').first.to_s.strip
      when 'EMAIL' then contact[:emails] << typed(unescape(value), params)
      when 'TEL' then contact[:phones] << typed(unescape(value), params)
      when 'URL' then contact[:urls] << typed(unescape(value), params)
      when 'ADR' then contact[:addresses] << typed(address_from_components(value), params)
      when 'NOTE' then contact[:notes] << { value: unescape(value), type: 'personal' }
      when 'ORG' then contact[:_orgs] << unescape(value).split(';').first.to_s.strip
      when 'TITLE' then contact[:_titles] << unescape(value)
      when 'BDAY' then contact[:birthday] = parse_birthday(value)
      when 'CATEGORIES' then contact[:favorite] = true if unescape(value).downcase.include?('favourite')
      end
    end
  end

  # Returns [property name, parameter list, raw value] for one unfolded line.
  def parse_line(line)
    line.split(':', 2).then do |head, value|
      head.to_s.split(';').then do |parts|
        # Strip any vCard grouping prefix (e.g. "item1.EMAIL").
        [parts.first.to_s.split('.').last.to_s.upcase, parts.drop(1), value.to_s]
      end
    end
  end

  def typed(value, params)
    { value: value, type: type_from_params(params) }
  end

  def type_from_params(params)
    params.map { |p| p.split('=', 2) }
          .select { |key, _| key.to_s.casecmp('TYPE').zero? }
          .flat_map { |_, val| val.to_s.delete('"').split(',') }
          .map { |val| VCARD_TO_TYPE[val.strip.upcase] }
          .compact
          .first || 'personal'
  end

  def address_from_components(value)
    unescape_components(value).values_at(0, 1, 2, 3, 4, 5, 6)
                              .map(&:to_s).map(&:strip).reject(&:empty?).join(', ')
  end

  def name_from_structured(value)
    unescape_components(value).values_at(3, 1, 2, 0, 4)
                              .map(&:to_s).map(&:strip).reject(&:empty?).join(' ')
  end

  def unescape_components(value)
    split_escaped(value.to_s, ';').map { |part| unescape(part) }
  end

  # Splits on a delimiter that is not backslash-escaped.
  def split_escaped(value, delimiter)
    value.to_s.chars.each_with_object([+'']) do |char, parts|
      if parts.last.end_with?('\\')
        parts.last << char
      elsif char == delimiter
        parts << +''
      else
        parts.last << char
      end
    end
  end

  # N is family; given; additional; prefixes; suffixes. We only keep a
  # free-form full name, so split it into family/given on the last space.
  def structured_name(name)
    name.to_s.strip.split(/\s+/).then do |parts|
      "#{escape(parts.last)};#{escape(parts.length > 1 ? parts.first : '')};;;"
    end
  end

  # ORG and TITLE are separate properties, so pair them up positionally and
  # fall back to a role that has only one of the two.
  def pair_roles(contact)
    [contact.delete(:_orgs), contact.delete(:_titles)].then do |orgs, titles|
      [orgs.length, titles.length].max.times do |index|
        contact[:roles] << { organization: orgs[index].to_s, title: titles[index].to_s, type: 'work' }
      end
    end
  end

  # --- Shared helpers -----------------------------------------------------

  def split_cards(text)
    [[], []].then do |cards, current|
      text.each_line do |raw|
        raw.strip.then do |line|
          case line.upcase
          when 'BEGIN:VCARD' then current.clear
          when 'END:VCARD' then cards << current.dup
          else current << line unless line.empty?
          end
        end
      end
      cards
    end
  end

  # RFC 6350 line unfolding: a CRLF followed by a space or tab is a continuation.
  def unfold(text) = text.gsub(/\r\n[ \t]/, '').gsub(/\n[ \t]/, '')

  # RFC 6350 caps lines at 75 octets; longer ones are folded with a leading space.
  def fold(line)
    line.chars.each_slice(74).map(&:join).join("#{EOL} ")
  end

  ESCAPES = { '\\' => '\\\\', "\n" => '\\n', ',' => '\\,', ';' => '\\;' }.freeze

  def escape(value)
    value.to_s.gsub(/[\\\n,;]/) { |char| ESCAPES.fetch(char, char) }
  end

  def unescape(value)
    value.to_s.gsub(/\\(.)/m) { ::Regexp.last_match(1).match?(/\An\z/i) ? "\n" : ::Regexp.last_match(1) }
  end

  def format_birthday(birthday)
    case birthday
    when Date then birthday.strftime('%Y%m%d')
    when String then birthday.delete('-')
    end.to_s
  end

  def parse_birthday(value)
    Contact.parse_birthday(value.to_s.strip.match?(/\A\d{8}\z/) ? dashed(value.to_s.strip) : value.to_s.strip)
  end

  def dashed(digits) = "#{digits[0, 4]}-#{digits[4, 2]}-#{digits[6, 2]}"

  def to_typed_hash(entry)
    entry.respond_to?(:to_h) && !entry.is_a?(Hash) ? entry.to_h : symbolize(entry)
  end

  def to_role_hash(entry)
    entry.respond_to?(:to_h) && !entry.is_a?(Hash) ? entry.to_h : symbolize(entry)
  end

  def symbolize(hash) = Hash(hash).transform_keys(&:to_sym)

  def blank?(value) = value.to_s.strip.empty?

  def blank_contact
    { id: nil, name: '', nickname: '', birthday: nil, favorite: false,
      emails: [], phones: [], urls: [], addresses: [], notes: [], roles: [],
      _orgs: [], _titles: [] }
  end

  def meaningful?(contact)
    !blank?(contact[:name]) || !blank?(contact[:nickname]) ||
      %i[emails phones urls addresses notes roles].any? { |key| contact[key].any? }
  end
end
