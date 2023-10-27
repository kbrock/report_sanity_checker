# monkey patch required for earlier versions
if !MiqReport.method_defined?(:menu_name=)
  class MiqReport
    alias_attribute :menu_name, :name
  end
end

#if !MiqExpression.method_defined?(:fields)
MiqExpression
class MiqExpression
  def fields(expression = exp)
    case expression
    when Array
      expression.flat_map { |x| fields(x) }
    when Hash
      return [] if expression.empty?

      if (val = expression["field"] || expression["count"] || expression[""])
        ret = []
        v = self.class.parse_field_or_tag(val)
        ret << v if v
        v = self.class.parse_field_or_tag(expression["value"].to_s)
        ret << v if v
        ret
      else
        fields(expression.values)
      end
    end
  end
end
#end

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
