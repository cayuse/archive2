module ReadonlyRecord
  extend ActiveSupport::Concern

  def readonly?
    true
  end

  class_methods do
    def readonly_attributes
      attribute_names
    end
  end
end


