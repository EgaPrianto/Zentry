class SleepEntry < ApplicationRecord
  belongs_to :user

  def sleep_duration
    ActiveSupport::Duration.build(self[:sleep_duration])
  end
end
