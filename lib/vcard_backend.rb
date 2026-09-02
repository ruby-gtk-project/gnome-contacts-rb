# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require_relative 'backend'
require_relative 'vcard'

module Backends
  # VCard directory backend for contact persistence.
  #
  # Each contact is one vCard 4.0 file named after its UID, in:
  #   ~/.local/share/ruby-contacts/vcards/
  #
  # This is the closest analogue of upstream's Evolution Data Server address
  # book: a directory of independent records that other tools can read.
  #
  class VCardBackend < Backend
    EXTENSIONS = %w[vcf vcard].freeze

    def initialize(path: nil)
      @path = path || default_path
    end

    def display_name = 'Local (vCard)'
    def location = @path

    def load
      ensure_directory
      vcard_files.flat_map { |file| VCard.parse_all(File.read(file)) }
    end

    def create(contact_hash)
      symbolize_keys(contact_hash).tap do |contact|
        contact[:id] ||= SecureRandom.uuid
        write_vcard(contact)
      end
    end

    def update(contact_hash)
      symbolize_keys(contact_hash).tap do |contact|
        unless contact[:id]
          raise ArgumentError, 'Contact ID required'
        end
        unless File.exist?(vcard_path(contact[:id]))
          raise "Contact not found: #{contact[:id]}"
        end

        write_vcard(contact)
      end
    end

    def delete(id)
      vcard_path(id).then do |path|
        if File.exist?(path)
          File.delete(path)
        end
        !File.exist?(path)
      end
    end

    private

      def default_path
        File.join(
          ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')),
          'ruby-contacts',
          'vcards',
        )
      end

      def ensure_directory = FileUtils.mkdir_p(@path)

      def vcard_files = Dir.glob(File.join(@path, "*.{#{EXTENSIONS.join(',')}}")).sort

    # The UID doubles as the filename, so keep it to characters a filesystem is
    # guaranteed to accept. Leading dots are stripped too: a name like
    # ".._escaped.vcf" is a dotfile, and Dir.glob would then never find it again.
      def vcard_path(id) = File.join(@path, "#{safe_name(id)}.vcf")

      def safe_name(id) = id.to_s.gsub(/[^A-Za-z0-9._-]/, '_').sub(/\A\.+/, '').then { |n| n.empty? ? 'contact' : n }

      def write_vcard(contact)
        ensure_directory
        File.write(vcard_path(contact[:id]), "#{VCard.dump(contact)}#{VCard::EOL}")
      end

      def symbolize_keys(hash) = hash.transform_keys(&:to_sym)
  end
end
