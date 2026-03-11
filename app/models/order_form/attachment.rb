# frozen_string_literal: true

class OrderForm
  class Attachment < ApplicationRecord
    belongs_to :order_form
    belongs_to :organization

    validates :file_name, presence: true
    validates :file_type, presence: true
    validates :file_url, presence: true
    validates :file_size,
      presence: true,
      numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :position,
      presence: true,
      numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end

# == Schema Information
#
# Table name: order_form_attachments
# Database name: primary
#
#  id              :uuid             not null, primary key
#  file_name       :string           not null
#  file_size       :integer          not null
#  file_type       :string           not null
#  file_url        :string           not null
#  position        :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  order_form_id   :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_order_form_attachments_on_order_form_id    (order_form_id)
#  index_order_form_attachments_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (order_form_id => order_forms.id)
#  fk_rails_...  (organization_id => organizations.id)
#
