# frozen_string_literal: true

require 'edataserver'
require_relative 'backend'

module Backends
  # EdsBackend lists the real Evolution Data Server address books already
  # configured on the user's system — the address books upstream itself
  # reads, via `E.SourceRegistry.list_sources(E.SOURCE_EXTENSION_ADDRESS_BOOK)`
  # in contacts-esd-setup.vala's `get_account_list`, and whose provider icon
  # upstream resolves off the source's `E.SourceGoa` extension in
  # contacts-accounts-list.vala and `get_icon_for_goa_account`.
  #
  # What this backend does NOT do: read or write the contacts inside those
  # books. The gemspec's `edataserver` dependency binds the `EDataServer` GI
  # namespace only — the source registry and its metadata — not `EBook`, the
  # separate namespace (a separate gem; not declared here) that opens a book
  # and queries its records. So #load always answers [] and the mutating
  # methods raise: the book is real, listed with its real name and its real
  # GOA-backed icon when it has one, but reading or writing through it needs
  # a binding this port does not have. Upstream's own split between EDS
  # (source discovery) and Folks/EBookClient (contact data) is the same
  # split; this is the first half of it.
  class EdsBackend < Backend
    def self.discover
      EDataServer::SourceRegistry.new
        .list_sources(EDataServer::SOURCE_EXTENSION_ADDRESS_BOOK)
        .map { |source| new(source) }
    rescue StandardError, GLib::Error => e
      warn "Could not query Evolution Data Server for address books: #{e.message}"
      []
    end

    def initialize(source)
      super()
      @source = source
    end

    attr_reader :source

    def display_name = @source.display_name
    def location = "eds:#{@source.uid}"

    # No EBookClient binding is available to write through (see the class
    # comment), so every EDS-discovered book is read-only in this port
    # regardless of whether the real source is writable.
    def readonly? = true

    def goa_account_id
      if @source.has_extension(EDataServer::SOURCE_EXTENSION_GOA)
        @source.get_extension(EDataServer::SOURCE_EXTENSION_GOA).account_id
      end
    end

    def load = []

    def create(_contact_hash)
      raise NotImplementedError, 'EdsBackend is read-only: this port has no EBook binding to write through'
    end

    def update(_contact_hash)
      raise NotImplementedError, 'EdsBackend is read-only: this port has no EBook binding to write through'
    end

    def delete(_id)
      raise NotImplementedError, 'EdsBackend is read-only: this port has no EBook binding to write through'
    end
  end
end
