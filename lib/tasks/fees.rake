# frozen_string_literal: true

namespace :fees do
  desc 'Fill missing fee_type'
  task fill_fee_type: :environment do
    Fee.where(fee_type: nil).find_each do |fee|
      fee_type = if fee.charge_id.blank? && fee.applied_add_on_id.blank?
                  'subscription'
                 elsif fee.charge_id.present?
                  'charge'
                 elsif fee.applied_add_on_id.present?
                  'add_on'
                 end

      fee.update!(fee_type: fee_type)
    end
  end
end
