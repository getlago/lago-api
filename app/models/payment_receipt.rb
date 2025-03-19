# frozen_string_literal: true

class PaymentReceipt < ApplicationRecord
  belongs_to :payment
  belongs_to :organization

  has_one_attached :file

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV["LAGO_API_URL"])
  end
end

# == Schema Information
#
# Table name: payment_receipts
#
#  id              :uuid             not null, primary key
#  number          :string           not null
#  payment_id      :uuid             not null
#  organization_id :uuid             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_payment_receipts_on_organization_id  (organization_id)
#  index_payment_receipts_on_payment_id       (payment_id) UNIQUE
#
