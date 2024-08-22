# frozen_string_literal: true

class ChangeFeesBoundaries < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          UPDATE fees
          SET properties = CONCAT (
            '{',
            '"from_datetime": "', (properties->>'from_date')::timestamp, '",',
            '"to_datetime": "', date_trunc('day', (properties->>'to_date')::date) + interval '1 day' - interval '1 millisecond', '",',
            '"charges_from_datetime":', CASE WHEN properties ? 'charges_from_date'
                                        THEN CONCAT('"', (properties->>'charges_from_date')::timestamp, '"')
                                        ELSE 'null' END, ',',
            '"charges_to_datetime":', CASE WHEN properties ? 'charges_to_date'
                                      THEN CONCAT('"', date_trunc('day', (properties->>'charges_to_date')::date) + interval '1 day' - interval '1 millisecond', '"')
                                      ELSE 'null' END,
            '}'
          )::jsonb
          WHERE (properties ? 'from_date');
          SQL
        end
      end
    end
  end
end
