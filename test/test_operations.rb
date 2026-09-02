# frozen_string_literal: true

require_relative 'test_helper'
require 'contact_store'
require 'operations'

class TestOperations < Minitest::Test
  include TempData

  def store = @store ||= ContactStore.new(backend: Backends::JsonBackend.new(path: json_path))
  def operations = @operations ||= Operations::OperationList.new

  def seed(*names)
    names.map { |name| store.add_contact(name: name, emails: [{ value: "#{name.downcase}@x.com", type: 'Work' }]) }
  end

  # --- Delete -------------------------------------------------------------

  def test_delete_operation_removes_and_restores
    seed('Ada', 'Grace').then do |(ada, _)|
      operations.execute(Operations::DeleteOperation.new(store, [ada]))
      assert_equal 1, store.n_contacts
      assert_equal 1, store.backend.load.length

      operations.undo_last
      assert_equal 2, store.n_contacts
      assert_equal 2, store.backend.load.length
    end
  end

  def test_delete_operation_handles_several_contacts
    seed('Ada', 'Grace', 'Alan').then do |contacts|
      Operations::DeleteOperation.new(store, contacts).tap do |operation|
        operations.execute(operation)
        assert_equal 0, store.n_contacts
        assert_equal 'Deleted 3 contacts', operation.description

        operations.undo_last
        assert_equal 3, store.n_contacts
      end
    end
  end

  def test_delete_describes_a_single_contact_by_name
    seed('Ada').then do |(ada)|
      assert_equal 'Deleted Ada', Operations::DeleteOperation.new(store, [ada]).description
    end
  end

  # --- Link ---------------------------------------------------------------

  def test_link_operation_merges_fields_into_the_first_contact
    store.add_contact(name: 'Ada Lovelace', emails: [{ value: 'ada@work.com', type: 'Work' }])
    store.add_contact(name: 'Ada Lovelace', phones: [{ value: '555', type: 'Mobile' }],
                      emails: [{ value: 'ada@home.com', type: 'Home' }])

    Operations::LinkOperation.new(store, store.contacts).tap do |operation|
      operations.execute(operation)

      assert_equal 1, store.n_contacts
      store.contacts.first.then do |merged|
        # Order follows the store's sort, so compare as sets: what matters is
        # that no value from either contact was dropped.
        assert_equal %w[ada@home.com ada@work.com], merged.emails.map(&:value).sort
        assert_equal ['555'], merged.phones.map(&:value)
      end
    end
  end

  def test_link_operation_can_be_undone
    seed('Ada', 'Grace')
    operations.execute(Operations::LinkOperation.new(store, store.contacts))
    assert_equal 1, store.n_contacts

    operations.undo_last
    assert_equal 2, store.n_contacts
    assert_equal %w[Ada Grace], store.contacts.map(&:name).sort
  end

  def test_link_keeps_a_favourite_and_the_first_avatar
    store.add_contact(name: 'Ada')
    store.add_contact(name: 'Ada', favorite: true,
                      avatar: { data: Base64.strict_encode64('PNGDATA'), media_type: 'image/png' })
    operations.execute(Operations::LinkOperation.new(store, store.contacts))

    store.contacts.first.then do |merged|
      assert_predicate merged, :favorite?
      assert_predicate merged, :avatar?
    end
  end

  # --- Unlink -------------------------------------------------------------

  def test_unlink_reverses_the_link_that_produced_the_contact
    seed('Ada', 'Grace')
    Operations::LinkOperation.new(store, store.contacts).tap do |link|
      operations.execute(link)
      assert_equal 1, store.n_contacts

      Operations::UnlinkOperation.new(store, store.contacts.first, link).tap do |unlink|
        assert_predicate unlink, :possible?
        unlink.run
        assert_equal 2, store.n_contacts
      end
    end
  end

  def test_unlink_reports_when_there_is_nothing_to_split
    seed('Ada')
    Operations::UnlinkOperation.new(store, store.contacts.first, nil).tap do |unlink|
      refute_predicate unlink, :possible?
      assert_raises(RuntimeError) { unlink.run }
    end
  end

  # --- Import -------------------------------------------------------------

  def test_import_operation_adds_and_removes
    Operations::ImportOperation.new(store, [{ id: 'a', name: 'Ada' }, { id: 'b', name: 'Grace' }]).tap do |operation|
      operations.execute(operation)
      assert_equal 2, store.n_contacts
      assert_equal 'Imported 2 contacts', operation.description

      operations.undo_last
      assert_equal 0, store.n_contacts
    end
  end

  def test_import_operation_is_not_reversable_when_nothing_was_new
    store.add_contact(id: 'a', name: 'Ada')
    Operations::ImportOperation.new(store, [{ id: 'a', name: 'Ada' }]).tap do |operation|
      operations.execute(operation)
      refute_predicate operation, :reversable?
      assert_equal 'No new contacts to import', operation.description
    end
  end

  # --- Operation list -----------------------------------------------------

  def test_operations_are_undone_most_recent_first
    seed('Ada', 'Grace', 'Alan')
    operations.execute(Operations::DeleteOperation.new(store, [store.contacts.first]))
    operations.execute(Operations::DeleteOperation.new(store, [store.contacts.first]))
    assert_equal 1, store.n_contacts

    operations.undo_last
    assert_equal 2, store.n_contacts
    operations.undo_last
    assert_equal 3, store.n_contacts
  end

  def test_undo_by_uuid
    seed('Ada')
    Operations::DeleteOperation.new(store, [store.contacts.first]).tap do |operation|
      operations.execute(operation)
      refute_nil operations.find(operation.uuid)
      operations.undo(operation.uuid)
      assert_equal 1, store.n_contacts
      assert_nil operations.find(operation.uuid), 'an undone operation leaves the list'
    end
  end

  def test_undo_last_returns_nil_when_there_is_nothing_reversable
    assert_nil operations.undo_last
  end

  def test_history_is_bounded
    seed('Ada')
    (Operations::OperationList::MAX_HISTORY + 5).times do
      operations.execute(Operations::ImportOperation.new(store, []))
    end
    assert_equal Operations::OperationList::MAX_HISTORY, operations.length
  end
end
