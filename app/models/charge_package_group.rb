class ChargePackageGroup < ApplicationRecord
  has_many :charge

  # TODO: check on validate functions
  # validates :current_package_count, presence: true
end
