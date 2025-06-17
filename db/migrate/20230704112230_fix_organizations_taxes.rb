# frozen_string_literal: true

class FixOrganizationsTaxes < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE taxes
          SET applied_to_organization = true
          FROM organizations
          WHERE organizations.id = taxes.organization_id
            AND organizations.vat_rate = taxes.rate
            AND applied_to_organization = false;
          SQL
        end
      end
    end
  end
end
