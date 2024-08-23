# frozen_string_literal: true

class AddEventRefrenceToQuantifiedEvents < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :events, :quantified_event, type: :uuid, index: true
    end
  end
end
