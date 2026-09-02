# frozen_string_literal: true

require 'date'
require 'base64'
require 'securerandom'
require_relative 'contact'
require_relative 'type_set'
require_relative 'im_service'

# VCard serialises and parses contacts as vCard 4.0 (RFC 6350).
#
# This is the Ruby counterpart of upstream's src/io/contacts-io-vcard-parser.vala
# and src/io/contacts-io-vcard-export-operation.vala, collapsed into one module
# because both directions share the same escaping and property grammar.
#
# Everything here works on plain contact hashes (the shape Contact#to_h and
# Contact.from_h speak), so it is equally usable by VCardBackend and by the
# import/export actions.
#
module VCard
  MIME_TYPE = 'text/vcard'
  EOL = "\r\n"

  # Fields whose type labels come from a TypeSet, and the property each maps to.
  TYPED_PROPERTIES = { emails: 'EMAIL', phones: 'TEL', urls: 'URL' }.freeze

  module_function

  # --- Export -------------------------------------------------------------

  # Serialises one contact hash into a single VCARD block (no trailing EOL).
  def dump(contact) = lines(contact).map { |line| fold(line) }.join(EOL)

  # Serialises many contact hashes into one file's worth of text.
  def dump_all(contacts) = "#{contacts.map { |contact| dump(contact) }.join(EOL)}#{EOL}"

  def lines(contact)
    [].tap do |out|
      out << 'BEGIN:VCARD'
      out << 'VERSION:4.0'
      if contact[:id]
        out << "UID:#{escape(contact[:id])}"
      end
      name_lines(out, contact)
      unless blank?(contact[:nickname])
        out << "NICKNAME:#{escape(contact[:nickname])}"
      end
      TYPED_PROPERTIES.each { |field, property| typed_lines(
        out,
        contact[field],
        property,
        field,
      ) }
      address_lines(out, contact[:addresses])
      im_lines(out, contact[:im_addresses])
      role_lines(out, contact[:roles])
      unless blank?(format_birthday(contact[:birthday]))
        out << "BDAY:#{format_birthday(contact[:birthday])}"
      end
      note_lines(out, contact[:notes])
      photo_line(out, contact[:avatar])
      if contact[:favorite]
        out << 'CATEGORIES:Favourite'
      end
      out << 'END:VCARD'
    end
  end

  def name_lines(out, contact)
    if blank?(contact[:name])
      display = nil
    else
      display = contact[:name]
    end
    structured = StructuredName.coerce(contact[:structured_name])
    if structured.empty? && display
      structured = StructuredName.from_full_name(display)
    end

    unless blank?(display || structured.to_s)
      out << "FN:#{escape(display || structured.to_s)}"
    end
    unless structured.empty?
      out << "N:#{structured_name_value(structured)}"
    end
    # Upstream's AliasChunk; there is no standard property, so use the
    # X-EVOLUTION one Evolution Data Server itself writes.
    unless blank?(contact[:alias])
      out << "X-EVOLUTION-ALIAS:#{escape(contact[:alias])}"
    end
  end

  def structured_name_value(structured)
    StructuredName::FIELDS.map { |field| escape(structured.public_send(field)) }.join(';')
  end

  def typed_lines(out, values, property, field)
    TypeSet.for_field(field).then do |type_set|
      each_value(values) do |value, type|
        out << "#{property};#{type_set.vcard_parameters(type).join(';')}:#{escape(value)}"
      end
    end
  end

  def address_lines(out, values)
    each_value(values) do |value, type|
      # ADR is PO box; extended; street; locality; region; postcode; country.
      # We keep a free-form address, so it goes in the street component.
      out << "ADR;#{TypeSet::GENERAL.vcard_parameters(type).join(';')}:;;#{escape(value)};;;;"
    end
  end

  def im_lines(out, values)
    Array(values).each do |entry|
      symbolize(entry.respond_to?(:to_h) && !entry.is_a?(Hash) ? entry.to_h : entry).then do |data|
        if blank?(data[:value])
          next
        end

        # IMPP carries a URI whose scheme is the service, which is how
        # Evolution and Folks round-trip IM addresses.
        out << "IMPP;X-SERVICE-TYPE=#{escape(data[:service])}:#{escape(data[:service])}:#{escape(data[:value])}"
      end
    end
  end

  def note_lines(out, values)
    each_value(values) { |value, _type| out << "NOTE:#{escape(value)}" }
  end

  def photo_line(out, avatar)
    Avatar.coerce(avatar).then do |photo|
      if photo && !photo.empty?
        out << "PHOTO:data:#{photo.media_type};base64,#{Base64.strict_encode64(photo.data)}"
      end
    end
  end

  def role_lines(out, roles)
    Array(roles).each do |role|
      to_hash(role).then do |data|
        unless blank?(data[:organization])
          out << "ORG:#{escape(data[:organization])}"
        end
        unless blank?(data[:title])
          out << "TITLE:#{escape(data[:title])}"
        end
      end
    end
  end

  def each_value(values)
    Array(values).each do |entry|
      to_hash(entry).then do |data|
        unless blank?(data[:value])
          yield(data[:value], data[:type])
        end
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
      derive_name(contact)
    end.then { |contact| meaningful?(contact) ? contact : nil }
  end

  def apply_property(contact, line)
    parse_line(line).then do |name, params, value|
      case name
      when 'UID' then contact[:id] = unescape(value)
      when 'FN' then contact[:name] = unescape(value)
      when 'N' then contact[:structured_name] = structured_name_from(value)
      when 'NICKNAME' then contact[:nickname] = unescape(value).split(',').first.to_s.strip
      when 'X-EVOLUTION-ALIAS' then contact[:alias] = unescape(value)
      when 'EMAIL' then contact[:emails] << typed(unescape(value), params, :emails)
      when 'TEL' then contact[:phones] << typed(unescape(value), params, :phones)
      when 'URL' then contact[:urls] << typed(unescape(value), params, :urls)
      when 'ADR' then contact[:addresses] << typed(address_from_components(value), params, :addresses)
      when 'IMPP', 'X-JABBER', 'X-AIM', 'X-SKYPE', 'X-ICQ', 'X-MSN', 'X-YAHOO', 'X-GOOGLE-TALK'
        contact[:im_addresses] << im_address_from(name, params, value)
      when 'NOTE' then contact[:notes] << { value: unescape(value), type: 'Home' }
      when 'ORG' then contact[:_orgs] << unescape(value).split(';').first.to_s.strip
      when 'TITLE' then contact[:_titles] << unescape(value)
      when 'BDAY' then contact[:birthday] = parse_birthday(value)
      when 'PHOTO', 'LOGO' then contact[:avatar] ||= photo_from(params, value)
      when 'CATEGORIES'
        if unescape(value).downcase.include?('favourite')
          contact[:favorite] = true
        end
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

  def typed(value, params, field)
    { value: value, type: type_label(params, field) }
  end

  # A custom label wins over the TYPE parameters, matching upstream's
  # lookup_by_parameters which checks X-GOOGLE-LABEL first.
  def type_label(params, field)
    parameter_values(params, TypeSet::X_GOOGLE_LABEL).first.then do |custom|
      custom || TypeSet.for_field(field).lookup_by_vcard_types(parameter_values(params, 'TYPE')).display_name
    end
  end

  def parameter_values(params, key)
    params.map { |p| p.split('=', 2) }
          .select { |name, _| name.to_s.casecmp(key).zero? }
          .flat_map { |_, val| val.to_s.delete('"').split(',') }
          .map(&:strip).reject(&:empty?)
  end

  def im_address_from(property, params, value)
    parameter_values(params, 'X-SERVICE-TYPE').first.then do |declared|
      unescape(value).then do |raw|
        # IMPP values are URIs ("skype:someone"); the X- properties name the
        # service in the property itself ("X-JABBER: someone").
        raw.include?(':') && property == 'IMPP' ? raw.split(':', 2) : [nil, raw]
      end.then do |scheme, address|
        {
          service: (declared || scheme || property.sub(/\AX-/, '').downcase.tr('_', '-')).to_s,
          value:   address.to_s.strip,
        }
      end
    end
  end

  def photo_from(params, value)
    unescape(value).strip.then do |raw|
      if raw.start_with?('data:')
        raw.split(',', 2).then { |header, payload| { data: payload.to_s, media_type: header[/data:([^;]+)/, 1] || 'image/png' } }
      elsif parameter_values(params, 'ENCODING').any? { |e| %w[B BASE64].include?(e.upcase) }
        { data: raw, media_type: media_type_from(params) }
      end
    end
  end

  def media_type_from(params)
    parameter_values(params, 'TYPE').first.then do |type|
      type.to_s.downcase.then { |t| t.empty? || t == 'photo' ? 'image/png' : "image/#{t}" }
    end
  end

  def address_from_components(value)
    unescape_components(value).values_at(
      0,
      1,
      2,
      3,
      4,
      5,
      6,
    )
                              .map(&:to_s).map(&:strip).reject(&:empty?).join(', ')
  end

  def structured_name_from(value)
    unescape_components(value).then do |parts|
      StructuredName.new(
        family:     parts[0].to_s,
        given:      parts[1].to_s,
        additional: parts[2].to_s,
        prefixes:   parts[3].to_s,
        suffixes:   parts[4].to_s,
      ).to_h
    end
  end

  # FN and N each fill in for the other when only one is present.
  def derive_name(contact)
    StructuredName.coerce(contact[:structured_name]).then do |structured|
      if blank?(contact[:name]) && !structured.empty?
        contact[:name] = structured.to_s
      end
      if structured.empty?
        contact[:structured_name] = StructuredName.from_full_name(contact[:name]).to_h
      end
    end
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

  # ORG and TITLE are separate properties, so pair them up positionally and
  # fall back to a role that has only one of the two.
  def pair_roles(contact)
    [contact.delete(:_orgs), contact.delete(:_titles)].then do |orgs, titles|
      [orgs.length, titles.length].max.times do |index|
        contact[:roles] << { organization: orgs[index].to_s, title: titles[index].to_s, type: 'Work' }
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
          else
            unless line.empty?
              current << line
            end
          end
        end
      end
      cards
    end
  end

  # RFC 6350 line unfolding: a CRLF followed by a space or tab is a continuation.
  def unfold(text) = text.gsub(/\r\n[ \t]/, '').gsub(/\n[ \t]/, '')

  # RFC 6350 caps lines at 75 octets; longer ones are folded with a leading space.
  def fold(line) = line.chars.each_slice(74).map(&:join).join("#{EOL} ")

  ESCAPES = { '\\' => '\\\\', "\n" => '\\n', ',' => '\\,', ';' => '\\;' }.freeze

  def escape(value) = value.to_s.gsub(/[\\\n,;]/) { |char| ESCAPES.fetch(char, char) }

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

  def to_hash(entry) = entry.respond_to?(:to_h) && !entry.is_a?(Hash) ? entry.to_h : symbolize(entry)

  def symbolize(hash) = Hash(hash).transform_keys(&:to_sym)

  def blank?(value) = value.to_s.strip.empty?

  def blank_contact
    {
      id:              nil,
      name:            '',
      alias:           '',
      nickname:        '',
      birthday:        nil,
      favorite:        false,
      structured_name: nil,
      avatar:          nil,
      emails:          [],
      phones:          [],
      urls:            [],
      addresses:       [],
      notes:           [],
      roles:           [],
      im_addresses:    [],
      _orgs:           [],
      _titles:         [],
    }
  end

  def meaningful?(contact)
    !blank?(contact[:name]) || !blank?(contact[:nickname]) || !blank?(contact[:alias]) ||
      %i[emails phones urls addresses notes roles im_addresses].any? { |key| contact[key].any? }
  end
end
