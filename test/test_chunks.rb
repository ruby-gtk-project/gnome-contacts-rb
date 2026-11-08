# frozen_string_literal: true

require_relative 'test_helper'
require 'contact'

# Mirrors upstream's per-field chunk tests (test/core/contacts-*-chunk-test.vala):
# addresses, email, full-name, nickname, notes, phones, roles, structured-name,
# urls. Upstream gives each field its own Chunk subclass with its own
# is_empty; this port collapses "value plus type" fields (email, phone, url,
# address, note) onto the single TypedValue class and keeps full-name /
# nickname as plain Contact string attributes, so the behavioural equivalent
# of each upstream chunk test is asserted here against whichever class or
# Contact field actually carries that behaviour, construction included.
class TestEmailAddressChunk < Minitest::Test
  def test_construction_keeps_value_and_type
    TypedValue.new(value: 'ada@analytical.engine', type: 'Work').then do |email|
      assert_equal 'ada@analytical.engine', email.value
      assert_equal 'Work', email.type
    end
  end

  def test_is_empty_when_blank_and_not_when_set
    assert_predicate TypedValue.new(value: '', type: 'Work'), :empty?
    refute_predicate TypedValue.new(value: 'ada@analytical.engine', type: 'Work'), :empty?
  end

  def test_empty_to_unempty_transition_on_a_contact
    Contact.new(id: '1', emails: [TypedValue.new(value: '', type: 'Work')]).then do |contact|
      assert_predicate contact.emails.first, :empty?
      contact.emails = [TypedValue.new(value: 'ada@analytical.engine', type: 'Work')]
      refute_predicate contact.emails.first, :empty?
    end
  end
end

class TestPhoneChunk < Minitest::Test
  def test_construction_keeps_value_and_type
    TypedValue.new(value: '+44 20 7946 0100', type: 'Mobile').then do |phone|
      assert_equal '+44 20 7946 0100', phone.value
      assert_equal 'Mobile', phone.type
    end
  end

  def test_is_empty_when_blank_and_not_when_set
    assert_predicate TypedValue.new(value: '   ', type: 'Mobile'), :empty?
    refute_predicate TypedValue.new(value: '555', type: 'Mobile'), :empty?
  end

  def test_empty_to_unempty_transition_on_a_contact
    Contact.new(id: '1', phones: [TypedValue.new(value: '', type: 'Home')]).then do |contact|
      assert_predicate contact.phones.first, :empty?
      contact.phones = [TypedValue.new(value: '555', type: 'Home')]
      refute_predicate contact.phones.first, :empty?
    end
  end
end

class TestUrlChunk < Minitest::Test
  def test_construction_keeps_value_and_type
    TypedValue.new(value: 'analytical.engine', type: 'Work').then do |url|
      assert_equal 'analytical.engine', url.value
      assert_equal 'Work', url.type
    end
  end

  def test_is_empty_when_blank_and_not_when_set
    assert_predicate TypedValue.new(value: '', type: 'Work'), :empty?
    refute_predicate TypedValue.new(value: 'analytical.engine', type: 'Work'), :empty?
  end
end

class TestAddressChunk < Minitest::Test
  def test_construction_keeps_value_and_type
    TypedValue.new(value: '12 Marylebone Rd, London', type: 'Home').then do |address|
      assert_equal '12 Marylebone Rd, London', address.value
      assert_equal 'Home', address.type
    end
  end

  def test_is_empty_when_blank_and_not_when_set
    assert_predicate TypedValue.new(value: '', type: 'Home'), :empty?
    refute_predicate TypedValue.new(value: '12 Marylebone Rd, London', type: 'Home'), :empty?
  end
end

class TestNoteChunk < Minitest::Test
  def test_construction_keeps_value_and_type
    TypedValue.new(value: 'First programmer', type: 'Personal').then do |note|
      assert_equal 'First programmer', note.value
      assert_equal 'Personal', note.type
    end
  end

  def test_is_empty_when_blank_and_not_when_set
    assert_predicate TypedValue.new(value: '', type: 'Personal'), :empty?
    refute_predicate TypedValue.new(value: 'First programmer', type: 'Personal'), :empty?
  end

  def test_empty_to_unempty_transition_on_a_contact
    Contact.new(id: '1', notes: [TypedValue.new(value: '', type: 'Personal')]).then do |contact|
      assert_predicate contact.notes.first, :empty?
      contact.notes = [TypedValue.new(value: 'First programmer', type: 'Personal')]
      refute_predicate contact.notes.first, :empty?
    end
  end
end

class TestRoleChunk < Minitest::Test
  def test_construction_keeps_organization_title_and_type
    Role.new(organization: 'Analytical Engine Co', title: 'Mathematician', type: 'Work').then do |role|
      assert_equal 'Analytical Engine Co', role.organization
      assert_equal 'Mathematician', role.title
      assert_equal 'Work', role.type
    end
  end

  # Upstream's RoleChunk is empty only when BOTH organization and title are
  # blank; either one alone is enough to make it non-empty.
  def test_is_empty_only_when_both_organization_and_title_are_blank
    assert_predicate Role.new(organization: '', title: '', type: 'Work'), :empty?
    refute_predicate Role.new(organization: 'Acme', title: '', type: 'Work'), :empty?
    refute_predicate Role.new(organization: '', title: 'Engineer', type: 'Work'), :empty?
    refute_predicate Role.new(organization: 'Acme', title: 'Engineer', type: 'Work'), :empty?
  end

  def test_empty_to_unempty_transition_on_a_contact
    Contact.new(id: '1', roles: [Role.new(organization: '', title: '', type: 'Work')]).then do |contact|
      assert_predicate contact.roles.first, :empty?
      contact.roles = [Role.new(organization: 'Acme', title: 'Engineer', type: 'Work')]
      refute_predicate contact.roles.first, :empty?
    end
  end
end

class TestStructuredNameChunk < Minitest::Test
  def test_construction_keeps_every_field
    StructuredName.new(family: 'Lovelace', given: 'Ada', additional: 'Byron', prefixes: 'Ms', suffixes: 'FRS').then do |name|
      assert_equal 'Lovelace', name.family
      assert_equal 'Ada', name.given
      assert_equal 'Byron', name.additional
      assert_equal 'Ms', name.prefixes
      assert_equal 'FRS', name.suffixes
    end
  end

  # Upstream's StructuredNameChunk is empty only when every one of its parts
  # is blank; any single part makes it non-empty.
  def test_is_empty_only_when_every_field_is_blank
    assert_predicate StructuredName.empty, :empty?
    refute_predicate StructuredName.empty.with(given: 'Ada'), :empty?
    refute_predicate StructuredName.empty.with(family: 'Lovelace'), :empty?
  end

  def test_empty_to_unempty_transition_on_a_contact
    Contact.new(id: '1', structured_name: StructuredName.empty).then do |contact|
      assert_predicate contact.structured_name, :empty?
      contact.structured_name = StructuredName.empty.with(given: 'Ada', family: 'Lovelace')
      refute_predicate contact.structured_name, :empty?
    end
  end
end

# Upstream's full-name chunk wraps Folks' single "full name" string field;
# this port keeps that as Contact#name directly, so the equivalent of
# upstream's is_empty check is the field being blank or not, and
# fetch_name/display_name are what actually consume it.
class TestFullNameChunk < Minitest::Test
  def test_blank_full_name_is_not_used_for_display
    Contact.new(id: '1', name: '').then do |contact|
      assert_equal '', contact.name
      assert_equal 'Unnamed Contact', contact.display_name
    end
  end

  def test_empty_to_unempty_transition_is_reflected_in_display_name
    Contact.new(id: '1', name: '').then do |contact|
      assert_equal 'Unnamed Contact', contact.display_name
      contact.name = 'Ada Lovelace'
      assert_equal 'Ada Lovelace', contact.display_name
    end
  end
end

# Upstream's nickname chunk is likewise a bare string field here.
class TestNicknameChunk < Minitest::Test
  def test_blank_nickname_does_not_feed_fetch_name
    Contact.new(id: '1', nickname: '', name: 'Ada Lovelace').then do |contact|
      assert_equal '', contact.nickname
      assert_equal 'Ada Lovelace', contact.fetch_name
    end
  end

  def test_empty_to_unempty_transition
    Contact.new(id: '1', nickname: '').then do |contact|
      assert_empty contact.nickname
      contact.nickname = 'Ada'
      refute_empty contact.nickname
    end
  end

  # fetch_name falls back to nickname only once alias, name and structured
  # name are all blank.
  def test_nickname_is_the_last_resort_in_fetch_name
    Contact.new(id: '1', nickname: 'Ada', name: '', alias_name: '', structured_name: StructuredName.empty).then do |contact|
      assert_equal 'Ada', contact.fetch_name
    end
  end
end
