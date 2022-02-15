# frozen_string_literal: true

class Organization < ApplicationRecord
  validates_presence_of :name
end
