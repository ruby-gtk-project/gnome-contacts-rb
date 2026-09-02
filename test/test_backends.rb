# frozen_string_literal: true

require_relative 'test_helper'
require 'contact'
require 'json_backend'
require 'vcard_backend'

# The same contract, run against every backend, so the two cannot drift apart.
module BackendContract
  include TempData

  def test_load_is_empty_to_begin_with
    assert_empty backend.load
  end

  def test_create_then_load_round_trips_every_field
    backend.create(contact_hash).then do |created|
      refute_nil created[:id]

      fresh_backend.load.then do |loaded|
        assert_equal 1, loaded.length
        Contact.from_h(loaded.first).then do |contact|
          assert_equal 'Ada Lovelace', contact.name
          assert_equal 'Ada', contact.nickname
          assert_equal ['ada@analytical.engine'], contact.emails.map(&:value)
          assert_equal ['+44 20 7946 0100'], contact.phones.map(&:value)
          assert_equal 'Mathematician at Analytical Engine Co', contact.role_display
          assert_equal Date.new(1815, 12, 10), contact.birthday
          assert_predicate contact, :favorite?
        end
      end
    end
  end

  def test_create_generates_an_id_when_missing
    refute_nil backend.create(contact_hash.reject { |k, _| k == :id })[:id]
  end

  def test_update_replaces_the_stored_record
    backend.create(contact_hash).then do |created|
      backend.update(created.merge(name: 'Augusta Ada King'))
      assert_equal 'Augusta Ada King', fresh_backend.load.first[:name]
      assert_equal 1, fresh_backend.load.length, 'update must not create a second record'
    end
  end

  def test_update_rejects_an_unknown_contact
    assert_raises(StandardError) { backend.update(contact_hash.merge(id: 'does-not-exist')) }
  end

  def test_delete_removes_the_record
    backend.create(contact_hash).then do |created|
      assert backend.delete(created[:id])
      assert_empty fresh_backend.load
    end
  end

  def test_delete_of_an_unknown_id_is_harmless
    assert backend.delete('does-not-exist')
  end

  def test_reports_a_display_name_and_location
    refute_empty backend.display_name
    refute_empty backend.location
  end

  private

  def contact_hash
    Contact.from_h(full_contact_attributes.merge(id: 'ada-1')).to_h
  end
end

class TestJsonBackend < Minitest::Test
  include BackendContract

  def backend = @backend ||= Backends::JsonBackend.new(path: json_path)
  def fresh_backend = Backends::JsonBackend.new(path: json_path)

  def test_survives_a_corrupt_file
    FileUtils.mkdir_p(File.dirname(json_path))
    File.write(json_path, 'not json at all')
    assert_empty capture_io { assert_empty backend.load }.first
  end

  def test_writes_readable_json
    backend.create(contact_hash)
    JSON.parse(File.read(json_path)).then do |data|
      assert_equal 1, data['version']
      assert_equal 1, data['contacts'].length
    end
  end
end

class TestVCardBackend < Minitest::Test
  include BackendContract

  def backend = @backend ||= Backends::VCardBackend.new(path: vcard_dir)
  def fresh_backend = Backends::VCardBackend.new(path: vcard_dir)

  def test_writes_one_file_per_contact
    backend.create(contact_hash)
    backend.create(contact_hash.merge(id: 'grace-1', name: 'Grace Hopper'))
    assert_equal 2, Dir.glob(File.join(vcard_dir, '*.vcf')).length
  end

  def test_reads_cards_written_by_other_tools
    FileUtils.mkdir_p(vcard_dir)
    File.write(File.join(vcard_dir, 'foreign.vcf'), <<~VCF)
      BEGIN:VCARD
      VERSION:3.0
      FN:Grace Hopper
      EMAIL;TYPE=INTERNET:grace@navy.mil
      END:VCARD
    VCF
    assert_equal 'Grace Hopper', backend.load.first[:name]
  end

  def test_sanitises_ids_used_as_filenames
    backend.create(contact_hash.merge(id: '../escape/attempt')).then do
      assert_empty Dir.glob(File.join(vcard_dir, '..', '*.vcf')) - Dir.glob(File.join(vcard_dir, '*.vcf'))
      assert_equal 1, Dir.glob(File.join(vcard_dir, '*.vcf')).length
    end
  end
end
