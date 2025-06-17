# frozen_string_literal: true

class SetDefaultPropertiesToCharges < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          -- Standard charges
          UPDATE charges
          SET properties = '{
            "amount":"0"
          }'
          WHERE charge_model = 0
          AND length(properties::text) = 2;

          -- Graduated charges
          UPDATE charges
          SET properties = '{
            "amount": "",
            "graduated_ranges": [
              {
                "from_value": 0,
                "to_value": null,
                "per_unit_amount": "0",
                "flat_amount": "0"
              }
            ]
          }'
          WHERE charge_model = 1
          AND length(properties::text) = 2;

          -- Package charges
          UPDATE charges
          SET properties = '{
            "package_size": 1,
            "amount": "0",
            "free_units": 0
          }'
          WHERE charge_model = 2
          AND length(properties::text) = 2;

          -- Percentage charges
          UPDATE charges
          SET properties = '{
            "rate": "0"
          }'
          WHERE charge_model = 3
          AND length(properties::text) = 2;

          -- Volume charges
          UPDATE charges
          SET properties = '{
            "amount": "",
            "volume_ranges": [
              {
                "from_value": 0,
                "to_value": null,
                "per_unit_amount": "0",
                "flat_amount": "0"
              }
            ]
          }'
          WHERE charge_model = 4
          AND length(properties::text) = 2;

          -- Graduated Percentage charges
          UPDATE charges
          SET properties = '{
            "graduated_percentage_ranges": [
              {
                "from_value": 0,
                "to_value": null,
                "rate": "0",
                "fixed_amount": "0",
                "flat_amount": "0"
              }
            ]
          }'
          WHERE charge_model = 5
          AND length(properties::text) = 2;
          SQL
        end
      end
    end
  end
end
