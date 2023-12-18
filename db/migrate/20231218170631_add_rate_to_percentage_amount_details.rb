# frozen_string_literal: true

class AddRateToPercentageAmountDetails < ActiveRecord::Migration[7.0]
  class Fee < ApplicationRecord
    belongs_to :charge, -> { with_discarded }, optional: true
  end

  def up
    percentage_fees = Fee.joins(:charge).merge(Charge.percentage).where.not(amount_details: {})

    percentage_fees.find_each do |fee|
      fee.update!(
        amount_details: fee.amount_details.except!('per_unit_amount').merge(
          rate: BigDecimal(fee.charge.properties['rate'].to_s),
        ),
      )
    end

    graduated_percentage_fees = Fee.joins(:charge).merge(Charge.graduated_percentage).where.not(amount_details: {})

    graduated_percentage_fees.find_each do |fee|
      fee.amount_details['graduated_percentage_ranges'] = fee.amount_details['graduated_percentage_ranges'].tap do |rs|
        rs.map do |range|
          rate = fee.charge.properties['graduated_percentage_ranges'].find do |r|
            r['from_value'] == range['from_value'] && r['to_value'] == range['to_value']
          end['rate']

          range.except!('per_unit_amount').merge!('rate' => BigDecimal(rate.to_s))
        end
      end
      fee.save!
    end
  end

  def down; end
end
