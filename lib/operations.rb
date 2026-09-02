# frozen_string_literal: true

require 'securerandom'

# Undoable operations, ported from upstream's src/contacts-operation.vala,
# src/contacts-operation-list.vala and the concrete operations beside them
# (delete, link, unlink, import).
#
# Upstream's operations are async because they talk to Evolution Data Server
# over D-Bus; with file backends they complete synchronously, so what remains
# is the part that matters to the user: each operation describes itself, some
# can be reversed, and the window offers an Undo for those that can.
#
module Operations
  # Base class: an operation knows how to run, how to describe itself, and
  # (sometimes) how to undo itself.
  class Operation
    attr_reader :uuid

    def initialize
      @uuid = SecureRandom.uuid
      @executed = false
    end

    def description = raise(NotImplementedError, "#{self.class}#description")
    def execute = raise(NotImplementedError, "#{self.class}#execute")

    # Only operations that have run and can be reversed offer an Undo button.
    def reversable? = false
    def executed? = @executed

    def run
      execute.tap { @executed = true }
    end

    def undo
      unless reversable?
        raise "#{self.class} cannot be undone"
      end

      _undo.tap { @executed = false }
    end

    private

      def _undo = raise(NotImplementedError, "#{self.class}#_undo")
  end

  # Deletes one or more contacts, remembering enough to put them back.
  class DeleteOperation < Operation
    def initialize(store, contacts)
      super()
      @store = store
      @contacts = Array(contacts)
      # Snapshotted up front: once a contact is deleted its Ruby wrapper points
      # at freed memory, so #description must not read from it afterwards.
      @names = @contacts.map(&:display_name)
      @undo_info = []
    end

    def description
      if @names.length == 1
        "Deleted #{@names.first}"
      else
        "Deleted #{@names.length} contacts"
      end
    end

    def reversable? = executed? && @undo_info.any?

    def execute
      @undo_info = @contacts.filter_map { |contact| @store.delete_contact(contact) }
    end

    private

    # Restored in reverse so the recorded positions still line up.
      def _undo
        @undo_info.reverse.map { |info| @store.restore_contact(info) }.tap { @undo_info = [] }
      end
  end

  # Merges several contacts into one. Upstream hands this to Folks, which links
  # personas; here the fields of every contact are merged into the first and
  # the others are deleted, which is the same outcome for a file backend.
  class LinkOperation < Operation
    def initialize(store, contacts)
      super()
      @store = store
      @contacts = Array(contacts)
      @primary = @contacts.first
      @snapshot = nil
      @removed = []
    end

    def description
      @contacts.length == 1 ? 'Linked 1 contact' : "Linked #{@contacts.length} contacts"
    end

    def reversable? = executed? && !@snapshot.nil?

    def execute
      @snapshot = @contacts.map(&:to_h)
      @store.update_contact(@primary, **merged_attributes)
      @removed = @contacts.drop(1).filter_map { |contact| @store.delete_contact(contact) }
      @primary
    end

    # Union of every field, keeping the primary contact's values first and
    # dropping duplicates.
    def merged_attributes
      {
        name:            first_non_empty(:name),
        alias_name:      first_non_empty(:alias_name),
        nickname:        first_non_empty(:nickname),
        birthday:        @contacts.map(&:birthday).compact.first,
        favorite:        @contacts.any?(&:favorite?),
        avatar:          @contacts.map(&:avatar).compact.first,
        structured_name: @contacts.map(&:structured_name).find { |n| n && !n.empty? },
        roles:           merge(:roles),
        im_addresses:    merge(:im_addresses),
      }
        .merge(Contact::MULTI_VALUE_FIELDS.to_h { |field| [field, merge(field)] })
    end

    private

      def first_non_empty(field)
        @contacts.map { |c| c.public_send(field).to_s }.find { |v| !v.strip.empty? }.to_s
      end

      def merge(field) = @contacts.flat_map { |c| c.public_send(field) }.reject(&:empty?).uniq

      def _undo
        @removed.reverse.each { |info| @store.restore_contact(info) }
        @store.update_contact(@primary, **Contact.from_h(@snapshot.first).to_h)
        @removed = []
        @snapshot = nil
        @primary
      end
  end

  # Splits a previously linked contact back into one contact per role/email
  # cluster. Without Folks personas there is nothing recorded to split on, so
  # this reverses the most recent link if there is one and otherwise reports
  # that there is nothing to unlink.
  class UnlinkOperation < Operation
    def initialize(store, contact, link_operation)
      super()
      @store = store
      @contact = contact
      @link_operation = link_operation
    end

    def description = "Unlinked #{@contact.display_name}"
    def possible? = !@link_operation.nil? && @link_operation.reversable?
    def reversable? = false

    def execute
      unless possible?
        raise 'This contact is not linked'
      end

      @link_operation.undo
    end
  end

  # Adds imported contacts, and can take them back out again.
  class ImportOperation < Operation
    def initialize(store, hashes)
      super()
      @store = store
      @hashes = hashes
      @imported = []
    end

    def description
      case @imported.length
      when 0 then 'No new contacts to import'
      when 1 then 'Imported 1 contact'
      else "Imported #{@imported.length} contacts"
      end
    end

    def reversable? = executed? && @imported.any?
    def imported = @imported

    def execute
      @imported = @store.import(@hashes)
    end

    private

      def _undo
        @imported.each { |contact| @store.delete_contact(contact) }
        @imported = []
      end
  end

  # Keeps the operations that have run, so the window can undo the last one and
  # so a toast can refer to an operation by uuid.
  #
  # Ported from upstream's OperationList, minus the async scheduling: upstream
  # delays execution so an operation can still be cancelled before it starts,
  # which only matters for D-Bus round trips.
  class OperationList
    MAX_HISTORY = 32

    def initialize
      @operations = []
    end

    def execute(operation)
      operation.run.tap do
        @operations << operation
        @operations.shift while @operations.length > MAX_HISTORY
      end
    end

    def find(uuid) = @operations.find { |op| op.uuid == uuid }

    def undo(uuid)
      find(uuid).then do |operation|
        if operation&.reversable?
          operation.undo
          @operations.delete(operation)
          operation
        end
      end
    end

    def last_reversable = @operations.reverse.find(&:reversable?)

    def undo_last
      last_reversable.then do |operation|
        if operation
          undo(operation.uuid)
        end
      end
    end

    def length = @operations.length
    def empty? = @operations.empty?
    def clear = @operations.clear
  end
end
