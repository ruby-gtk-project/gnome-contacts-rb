# frozen_string_literal: true

# ImService maps an instant-messaging service identifier to its display name.
#
# A direct port of upstream's src/contacts-im-service.vala, including the same
# service list and the same fallback of showing the raw identifier when it is
# not one we know.
#
module ImService
  SERVICES = {
    'aim'         => 'AOL Instant Messenger',
    'facebook'    => 'Facebook',
    'gadugadu'    => 'Gadu-Gadu',
    'google-talk' => 'Google Talk',
    'groupwise'   => 'Novell Groupwise',
    'icq'         => 'ICQ',
    'irc'         => 'IRC',
    'jabber'      => 'Jabber',
    'lj-talk'     => 'Livejournal',
    'local-xmpp'  => 'Local network',
    'msn'         => 'Windows Live Messenger',
    'myspace'     => 'MySpace',
    'mxit'        => 'MXit',
    'napster'     => 'Napster',
    'ovi-chat'    => 'Ovi Chat',
    'qq'          => 'Tencent QQ',
    'sametime'    => 'IBM Lotus Sametime',
    'silc'        => 'SILC',
    'sip'         => 'sip',
    'skype'       => 'Skype',
    'tel'         => 'Telephony',
    'trepia'      => 'Trepia',
    'yahoo'       => 'Yahoo! Messenger',
    'yahoojp'     => 'Yahoo! Messenger',
    'zephyr'      => 'Zephyr',
  }.freeze

  module_function

  def display_name(service) = SERVICES.fetch(service.to_s, service.to_s)

  def identifiers = SERVICES.keys

  # Display names for a dropdown, de-duplicated (two Yahoo entries share one).
  def display_names = SERVICES.values.uniq

  def identifier_for(display_name)
    SERVICES.key(display_name) || display_name.to_s
  end
end
