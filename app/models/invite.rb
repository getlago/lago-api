# frozen_string_literal: true

class Invite < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :recipient, class_name: "Membership", foreign_key: :membership_id, optional: true

  INVITE_STATUS = %i[
    pending
    accepted
    revoked
  ].freeze

  enum :status, INVITE_STATUS

  validates :email, email: true
  validates :token, uniqueness: true

  normalizes :email, with: ->(email) { EmailSanitizer.call(email) }

  # NOTE: Emails are saved with the case the user typed, so this lookup ignores case.
  def existing_user
    User.find_by("lower(email) = ?", email.to_s.downcase)
  end

  def existing_user?
    existing_user.present?
  end

  def login_method_allowed?(login_method)
    organization.authentication_methods.include?(login_method)
  end

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end

  def mark_as_accepted!(timestamp = Time.current)
    self.accepted_at ||= timestamp
    accepted!
  end
end

# == Schema Information
#
# Table name: invites
# Database name: primary
#
#  id              :uuid             not null, primary key
#  accepted_at     :datetime
#  email           :string           not null
#  revoked_at      :datetime
#  roles           :string           default([]), not null, is an Array
#  status          :integer          default("pending"), not null
#  token           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  membership_id   :uuid
#  organization_id :uuid             not null
#
# Indexes
#
#  index_invites_on_membership_id    (membership_id)
#  index_invites_on_organization_id  (organization_id)
#  index_invites_on_token            (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (membership_id => memberships.id)
#  fk_rails_...  (organization_id => organizations.id)
#
