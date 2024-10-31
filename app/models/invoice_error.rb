# frozen_string_literal: true

class InvoiceError < ApplicationRecord
  # NOTE! Invoice errors will have the same id as the invoice they belong to.
  def self.create_for(invoice:, error:)
    return unless invoice

    create(id: invoice.id,
      backtrace: error.backtrace,
      error: error.inspect.to_json,
      invoice: invoice.to_json(except: :file),
      subscriptions: invoice.subscriptions.to_json)
  end
end

# == Schema Information
#
# Table name: invoice_errors
#
#  id            :uuid             not null, primary key
#  backtrace     :text
#  error         :json
#  invoice       :json
#  subscriptions :json
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
