# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# ruby-gnome must be required BEFORE minitest/autorun.
#
# Both register an at_exit hook, and at_exit hooks run last-in-first-out.
# ruby-gnome's hook tears down its GLib<->Ruby callback bridge, so if it is
# required second its hook runs *first* — before minitest has run a single
# test — and every signal_connect block silently stops firing. The symptom is
# baffling: signal_connect still returns a handler id, but GLib reports
# "no handlers connected to the 'activate' signal", and UI tests pass
# vacuously because their assertions never execute.
require 'adwaita'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

# Gives each test its own throwaway XDG data directory, so a test run can
# never touch the developer's real address book.
module TempData
  def setup
    super
    @tmpdir = Dir.mktmpdir('gnome-contacts-rb')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    super
  end

  attr_reader :tmpdir

  def json_path = File.join(tmpdir, 'contacts.json')
  def vcard_dir = File.join(tmpdir, 'vcards')

  # A contact with every field populated, for round-trip assertions.
  def full_contact_attributes
    {
      name: 'Ada Lovelace',
      nickname: 'Ada',
      birthday: '1815-12-10',
      favorite: true,
      alias_name: 'Ada L',
      structured_name: { given: 'Ada', family: 'Lovelace', additional: 'Byron',
                         prefixes: 'Ms', suffixes: 'FRS' },
      im_addresses: [{ value: 'ada@jabber.org', service: 'jabber' }],
      emails: [{ value: 'ada@analytical.engine', type: 'Work' }],
      phones: [{ value: '+44 20 7946 0100', type: 'Home' }],
      urls: [{ value: 'analytical.engine', type: 'Work' }],
      addresses: [{ value: '12 Marylebone Rd, London', type: 'Home' }],
      notes: [{ value: "First programmer; wrote note G, 1843", type: 'Personal' }],
      roles: [{ organization: 'Analytical Engine Co', title: 'Mathematician', type: 'Work' }]
    }
  end
end
