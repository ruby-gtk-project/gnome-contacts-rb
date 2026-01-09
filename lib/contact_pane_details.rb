# frozen_string_literal: true

require 'gtk4'

# ContactPaneDetails displays the contact fields (email, phone, etc.)
#
class ContactPaneDetails
  def build
    container.tap do |c|
      c.child = list_box

      list_box.tap do |lb|
        lb.append(email_row)
        lb.append(phone_row)

        email_row.tap do |row|
          row.child = email_box

          email_box.tap do |eb|
            eb.append(email_icon)
            eb.append(email_label_box)

            email_label_box.tap do |elb|
              elb.append(email_type_label)
              elb.append(email_value)
            end
          end
        end

        phone_row.tap do |row|
          row.child = phone_box

          phone_box.tap do |pb|
            pb.append(phone_icon)
            pb.append(phone_label_box)

            phone_label_box.tap do |plb|
              plb.append(phone_type_label)
              plb.append(phone_value)
            end
          end
        end
      end
    end
  end

  def update(contact)
    email_str = extract_email(contact)
    phone_str = extract_phone(contact)

    email_value.label = email_str.empty? ? '—' : email_str
    phone_value.label = phone_str.empty? ? '—' : phone_str

    email_row.visible = !email_str.empty?
    phone_row.visible = !phone_str.empty?
  end

  def container
    @container ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.vexpand = true
      sw.hscrollbar_policy = :never
    end
  end

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |lb|
      lb.selection_mode = :none
      lb.add_css_class('boxed-list')
      lb.margin_top = 12
      lb.margin_bottom = 12
      lb.margin_start = 24
      lb.margin_end = 24
    end
  end

  # Email row widgets

  def email_row
    @email_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.activatable = true
    end
  end

  def email_box
    @email_box ||= Gtk::Box.new(:horizontal, 12).tap do |eb|
      eb.margin_top = 12
      eb.margin_bottom = 12
      eb.margin_start = 12
      eb.margin_end = 12
    end
  end

  def email_icon
    @email_icon ||= Gtk::Image.new.tap do |i|
      i.icon_name = 'mail-symbolic'
      i.add_css_class('dim-label')
    end
  end

  def email_label_box
    @email_label_box ||= Gtk::Box.new(:vertical, 2).tap do |elb|
      elb.hexpand = true
    end
  end

  def email_type_label
    @email_type_label ||= Gtk::Label.new.tap do |l|
      l.label = 'Email'
      l.xalign = 0
      l.add_css_class('dim-label')
      l.add_css_class('caption')
    end
  end

  def email_value
    @email_value ||= Gtk::Label.new.tap do |l|
      l.xalign = 0
      l.selectable = true
    end
  end

  # Phone row widgets

  def phone_row
    @phone_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.activatable = true
    end
  end

  def phone_box
    @phone_box ||= Gtk::Box.new(:horizontal, 12).tap do |pb|
      pb.margin_top = 12
      pb.margin_bottom = 12
      pb.margin_start = 12
      pb.margin_end = 12
    end
  end

  def phone_icon
    @phone_icon ||= Gtk::Image.new.tap do |i|
      i.icon_name = 'phone-symbolic'
      i.add_css_class('dim-label')
    end
  end

  def phone_label_box
    @phone_label_box ||= Gtk::Box.new(:vertical, 2).tap do |plb|
      plb.hexpand = true
    end
  end

  def phone_type_label
    @phone_type_label ||= Gtk::Label.new.tap do |l|
      l.label = 'Phone'
      l.xalign = 0
      l.add_css_class('dim-label')
      l.add_css_class('caption')
    end
  end

  def phone_value
    @phone_value ||= Gtk::Label.new.tap do |l|
      l.xalign = 0
      l.selectable = true
    end
  end

  private

  def extract_email(contact)
    if contact.respond_to?(:primary_email) && contact.primary_email
      contact.primary_email.address.to_s
    elsif contact.respond_to?(:emails) && contact.emails.any?
      contact.emails.first.address.to_s
    elsif contact.respond_to?(:email)
      contact.email.to_s
    else
      ''
    end
  end

  def extract_phone(contact)
    if contact.respond_to?(:primary_phone) && contact.primary_phone
      contact.primary_phone.number.to_s
    elsif contact.respond_to?(:phones) && contact.phones.any?
      contact.phones.first.number.to_s
    elsif contact.respond_to?(:phone)
      contact.phone.to_s
    else
      ''
    end
  end
end
