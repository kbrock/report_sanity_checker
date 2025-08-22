# this should come into play in Spasky
if !MiqExpression::Field.method_defined?(:virtual_reflection?)
  class MiqExpression::Target
    # @return true if column is a database column
    def db_column?
      target.has_attribute?(column) ||
        target.try(:attribute_alias?, column)
    end
  end
  class MiqExpression::Field
    # TODO: add to MiqExpression::Field
    def virtual_reflection?
      associations.present? && (model.follow_associations_with_virtual(associations) != model.follow_associations(associations))
    rescue ArgumentError
      # polymorphic is throwing us
      # assume the worst
      true
    end
  end
end
