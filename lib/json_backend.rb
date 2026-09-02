# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require_relative 'backend'

module Backends
  # JSON file backend for contact persistence.
  #
  # Stores contacts in a single JSON file at:
  #   ~/.local/share/ruby-contacts/contacts.json
  #
  class JsonBackend < Backend
    VERSION = 1

    def initialize(path: nil)
      @path = path || default_path
    end

    def display_name = 'Local (JSON)'
    def location = @path

    def load
      ensure_directory
      read_file.tap do |data|
        notify_prepared
        notify_quiescent
      end['contacts'].to_a.map { |c| symbolize_keys(c) }
    end

    def create(contact_hash)
      contact_hash.transform_keys(&:to_s).tap do |contact|
        contact['id'] ||= generate_id
        read_file.tap do |data|
          data['contacts'] = (data['contacts'] || []) << contact
          write_file(data)
        end
      end.then { |c| symbolize_keys(c) }
    end

    def update(contact_hash)
      contact_hash.transform_keys(&:to_s).tap do |contact|
        read_file.tap do |data|
          data['contacts'].to_a
            .find_index { |c| c['id'] == contact['id'] }
            .then do |index|
              unless index
                raise "Contact not found: #{contact['id']}"
              end
              data['contacts'][index] = contact
              write_file(data)
            end
        end
      end.then { |c| symbolize_keys(c) }
    end

    def delete(id)
      read_file.tap do |data|
        data['contacts'].to_a.tap do |contacts|
          contacts.reject! { |c| c['id'] == id }.tap do |deleted|
            if deleted
              write_file(data.merge('contacts' => contacts))
            end
          end
        end
      end['contacts'].to_a.none? { |c| c['id'] == id }
    end

    private

      def default_path
        File.join(
          ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')),
          'ruby-contacts',
          'contacts.json',
        )
      end

      def ensure_directory
        FileUtils.mkdir_p(File.dirname(@path))
      end

      def read_file
        File.exist?(@path)
          .then { |exists| exists ? JSON.parse(File.read(@path)) : empty_data }
      rescue JSON::ParserError => e
        warn "Error parsing #{@path}: #{e.message}"
        empty_data
      end

      def empty_data = { 'version' => VERSION, 'contacts' => [] }

      def write_file(data)
        ensure_directory
        File.write(@path, JSON.pretty_generate(data.merge('version' => VERSION)))
      end

    # Deep, so nested values (emails, roles, ...) come back symbol-keyed and
    # match what VCardBackend returns. Contact.from_h accepts either, but the
    # two backends agreeing keeps callers from having to care which is in use.
      def symbolize_keys(value)
        case value
        when Hash then value.to_h { |key, val| [key.to_sym, symbolize_keys(val)] }
        when Array then value.map { |val| symbolize_keys(val) }
        else value
        end
      end
  end
end
