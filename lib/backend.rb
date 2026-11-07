# frozen_string_literal: true

require 'securerandom'

module Backends
  # Abstract backend interface for contact persistence.
  #
  # All backends must implement these methods to provide storage
  # functionality. This allows swapping between JSON, VCard, or
  # other backends.
  #
  class Backend
    # Signal-like callbacks for async operations
    attr_accessor :on_prepared, :on_quiescent

    # Loads all contacts from the backend.
    #
    # @return [Array<Hash>] Array of contact hashes
    def load
      raise NotImplementedError, "#{self.class}#load must be implemented"
    end

    # Saves a new contact to the backend.
    #
    # @param contact_hash [Hash] Contact data to save
    # @return [Hash] The saved contact (may include generated :id)
    def create(contact_hash)
      raise NotImplementedError, "#{self.class}#create must be implemented"
    end

    # Updates an existing contact in the backend.
    #
    # @param contact_hash [Hash] Contact data with :id key
    # @return [Hash] The updated contact
    def update(contact_hash)
      raise NotImplementedError, "#{self.class}#update must be implemented"
    end

    # Deletes a contact from the backend.
    #
    # @param id [String] Contact ID to delete
    # @return [Boolean] true if deleted, false if not found
    def delete(id)
      raise NotImplementedError, "#{self.class}#delete must be implemented"
    end

    # Returns the backend's display name (for UI).
    #
    # @return [String] Human-readable backend name
    def display_name
      raise NotImplementedError, "#{self.class}#display_name must be implemented"
    end

    # Returns whether the backend is read-only.
    #
    # @return [Boolean] true if read-only
    def readonly? = false

    # Returns the path/location of the data store.
    #
    # @return [String] Path or URI to data
    def location
      raise NotImplementedError, "#{self.class}#location must be implemented"
    end

    # The GNOME Online Accounts account id backing this address book, or nil
    # when the book is not GOA-provisioned (every backend this port ships
    # today). Upstream reads this off the E.Source's SOURCE_EXTENSION_GOA
    # extension (contacts-accounts-list.vala); a backend tied to a real GOA
    # account overrides this with that id.
    def goa_account_id = nil

    protected

      def generate_id = SecureRandom.uuid
      def notify_prepared = on_prepared&.call
      def notify_quiescent = on_quiescent&.call
  end
end
