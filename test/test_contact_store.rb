# frozen_string_literal: true

require_relative 'test_helper'
require 'contact_store'

class TestContactStore < Minitest::Test
  include TempData

  def store = @store ||= ContactStore.new(backend: Backends::JsonBackend.new(path: json_path))

  # Regression: add_contact used to normalise its arguments and then hand them
  # to Contact.from_h, which normalised them a second time and wrapped each
  # TypedValue inside another one.
  def test_add_contact_does_not_double_wrap_typed_values
    store.add_contact(**full_contact_attributes).then do |contact|
      assert_equal 'ada@analytical.engine', contact.emails.first.value
      assert_equal 'work', contact.emails.first.type
      assert_equal 'Analytical Engine Co', contact.roles.first.organization
    end
  end

  def test_add_contact_persists_through_a_reload
    store.add_contact(**full_contact_attributes)
    ContactStore.new(backend: Backends::JsonBackend.new(path: json_path)).then do |reloaded|
      reloaded.load
      assert_equal 1, reloaded.n_contacts
      assert_equal 'ada@analytical.engine', reloaded.contacts.first.emails.first.value
    end
  end

  def test_update_contact_writes_through_to_the_backend
    store.add_contact(name: 'Ada').then do |contact|
      store.update_contact(contact, name: 'Augusta', emails: [{ value: 'a@b.com', type: 'work' }])
      assert_equal 'Augusta', contact.name
      assert_equal 'a@b.com', store.backend.load.first[:emails].first[:value]
    end
  end

  def test_delete_and_restore
    store.add_contact(name: 'Ada').then do |contact|
      store.delete_contact(contact).then do |undo|
        assert_equal 0, store.n_contacts
        assert_empty store.backend.load

        store.restore_contact(undo)
        assert_equal 1, store.n_contacts
        assert_equal 1, store.backend.load.length
      end
    end
  end

  def test_contacts_are_sorted_with_favourites_first
    ['Zoe', 'Ada', 'Mia'].each { |name| store.add_contact(name: name) }
    assert_equal %w[Ada Mia Zoe], store.contacts.map(&:name)

    store.set_favorite(store.contacts.last, true)
    assert_equal %w[Zoe Ada Mia], store.contacts.map(&:name)
  end

  def test_sorting_survives_a_rename
    ['Zoe', 'Ada'].each { |name| store.add_contact(name: name) }
    store.update_contact(store.contacts.first, name: 'Zach')
    assert_equal %w[Zach Zoe], store.contacts.map(&:name)
  end

  def test_query_filters_across_every_searchable_field
    store.add_contact(**full_contact_attributes)
    store.add_contact(name: 'Grace Hopper')

    { 'ada' => 1, 'analytical' => 1, 'marylebone' => 1, '7946' => 1,
      'mathematician' => 1, 'hopper' => 1, '' => 2, 'nobody' => 0 }.each do |query, expected|
      store.query = query
      assert_equal expected, store.n_visible, "query #{query.inspect}"
    end
  end

  def test_query_is_case_insensitive
    store.add_contact(name: 'Ada Lovelace')
    store.query = 'LOVELACE'
    assert_equal 1, store.n_visible
  end

  def test_selection_survives_a_resort
    store.add_contact(name: 'Zoe')
    store.add_contact(name: 'Ada').then do |ada|
      store.select_contact(ada)
      store.set_favorite(store.contacts.last, true)
      assert_equal 'Ada', store.selected_contact.name, 'the cursor should stay on the same contact'
    end
  end

  def test_import_skips_contacts_whose_id_is_already_known
    store.add_contact(**full_contact_attributes.merge(id: 'ada-1'))
    store.import([{ id: 'ada-1', name: 'Ada Lovelace' }, { id: 'grace-1', name: 'Grace Hopper' }]).then do |imported|
      assert_equal 1, imported.length
      assert_equal 'Grace Hopper', imported.first.name
      assert_equal 2, store.n_contacts
    end
  end

  def test_empty_predicate
    assert_predicate store, :empty?
    store.add_contact(name: 'Ada')
    refute_predicate store, :empty?
  end
end
