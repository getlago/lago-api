# frozen_string_literal: true

namespace :fees do
  desc 'Fill missing fee_type'
  task fill_fee_type: :environment do
    Fee.where(fee_type: nil).find_each do |fee|
      next fee.add_on! if fee.applied_add_on_id.present?
      next fee.charge! if fee.charge_id.present?

      fee.subscription!
    end
  end

  desc 'Migrate boundaries'
  task migrate_boundaries: :environment do
    Fee.find_each do |fee|
      next if fee.properties['from_datetime'].present?
      next if fee.properties['from_date'].blank?

      fee.properties = {
        'from_datetime' => fee.properties['from_date'].to_date.beginning_of_day,
        'to_datetime' => fee.properties['to_date'].to_date.end_of_day,
        'charges_from_datetime' => fee.properties['charges_from_date'].to_date.beginning_of_day,
        'charges_to_datetime' => fee.properties['charges_to_date'].to_date.end_of_day,
      }
      fee.save!
    end
  end
end
