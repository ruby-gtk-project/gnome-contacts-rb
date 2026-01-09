# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require_relative 'backend'

module Backends
  # VCard directory backend for contact persistence.
  #
  # Supports all contact fields via VCard 4.0 properties.
  #
  class VCardBackend < Backend
    def initialize(path: nil)
      @path = path || default_path
    end

    def display_name = 'Local (VCard)'
    def location = @path

    def load
      ensure_directory
      Dir.glob(File.join(@path, '*.vcf'))
        .map { |file| parse_vcard(File.read(file)) }
        .compact
    end

    def create(contact_hash)
      symbolize_keys(contact_hash).tap do |contact|
        contact[:id] ||= SecureRandom.uuid
        write_vcard(contact)
      end
    end

    def update(contact_hash)
      symbolize_keys(contact_hash).tap do |contact|
        raise 'Contact ID required' unless contact[:id]
        raise 'Contact not found' unless File.exist?(vcard_path(contact[:id]))
        write_vcard(contact)
      end
    end

    def delete(id)
      vcard_path(id).tap do |path|
        File.exist?(path).tap do |exists|
          File.delete(path) if exists
        end
      end.then { |path| !File.exist?(path) }
    end

    private

    def default_path
      File.join(
        ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')),
        'ruby-contacts',
        'vcards'
      )
    end

    def ensure_directory = FileUtils.mkdir_p(@path)

    def vcard_path(id) = File.join(@path, "#{id}.vcf")

    def write_vcard(contact)
      build_vcard_lines(contact).join("\r\n").tap do |content|
        File.write(vcard_path(contact[:id]), "#{content}\r\n")
      end
    end

    def build_vcard_lines(contact)
      [].tap do |lines|
        lines << 'BEGIN:VCARD'
        lines << 'VERSION:4.0'
        lines << "UID:#{contact[:id]}"
        lines << "FN:#{escape(contact[:name])}" unless contact[:name].to_s.empty?
        lines << "NICKNAME:#{escape(contact[:nickname])}" unless contact[:nickname].to_s.empty?
        lines << "EMAIL:#{escape(contact[:email])}" unless contact[:email].to_s.empty?
        lines << "TEL:#{escape(contact[:phone])}" unless contact[:phone].to_s.empty?
        lines << "ADR:;;#{escape(contact[:address])};;;;" unless contact[:address].to_s.empty?
        lines << "URL:#{escape(contact[:url])}" unless contact[:url].to_s.empty?
        lines << "BDAY:#{format_birthday(contact[:birthday])}" if contact[:birthday]
        lines << "NOTE:#{escape(contact[:notes])}" unless contact[:notes].to_s.empty?
        lines << "ORG:#{escape(contact[:organization])}" unless contact[:organization].to_s.empty?
        lines << "TITLE:#{escape(contact[:title])}" unless contact[:title].to_s.empty?
        lines << 'END:VCARD'
      end
    end

    def format_birthday(birthday)
      birthday.then do |b|
        if b.is_a?(Date)
          b.strftime('%Y%m%d')
        elsif b.is_a?(String) && !b.empty?
          b.gsub('-', '')
        end
      end
    end

    def parse_vcard(content)
      content.include?('BEGIN:VCARD').then do |is_vcard|
        if is_vcard
          content.each_line.each_with_object({}) do |line, contact|
            line.strip.tap do |l|
              case l
              when /^UID:(.+)$/i then contact[:id] = unescape($1)
              when /^FN:(.+)$/i then contact[:name] = unescape($1)
              when /^NICKNAME:(.+)$/i then contact[:nickname] = unescape($1)
              when /^EMAIL[^:]*:(.+)$/i then contact[:email] = unescape($1)
              when /^TEL[^:]*:(.+)$/i then contact[:phone] = unescape($1)
              when /^ADR[^:]*:;;([^;]*)/i then contact[:address] = unescape($1)
              when /^URL[^:]*:(.+)$/i then contact[:url] = unescape($1)
              when /^BDAY:(.+)$/i then contact[:birthday] = parse_birthday($1)
              when /^NOTE:(.+)$/i then contact[:notes] = unescape($1)
              when /^ORG[^:]*:(.+)$/i then contact[:organization] = unescape($1)
              when /^TITLE:(.+)$/i then contact[:title] = unescape($1)
              end
            end
          end.tap { |c| c[:id] ||= SecureRandom.uuid }
        end
      end
    end

    def parse_birthday(value)
      value.to_s.strip.then do |v|
        if v.match?(/^\d{8}$/)
          Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i) rescue v
        elsif v.match?(/^\d{4}-\d{2}-\d{2}$/)
          Date.parse(v) rescue v
        else
          v.empty? ? nil : v
        end
      end
    end

    def escape(value)
      value.to_s
        .gsub('\\', '\\\\')
        .gsub("\n", '\\n')
        .gsub(',', '\\,')
        .gsub(';', '\\;')
    end

    def unescape(value)
      value.to_s
        .gsub('\\n', "\n")
        .gsub('\\,', ',')
        .gsub('\\;', ';')
        .gsub('\\\\', '\\')
    end

    def symbolize_keys(hash) = hash.transform_keys(&:to_sym)
  end
end
