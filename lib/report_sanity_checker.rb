require_relative "report_sanity_checker/version"
require_relative "report_sanity_checker/table"

class ReportSanityChecker
  attr_accessor :pattern
  attr_accessor :verbose

  attr_accessor :columns

  #                 0      1        2       3     4      5      6    7      8
  HEADERS      = %w(column relation virtual sql   src    alias  sort hidden cond)
  HEADERS_SHOW =   [true,  false,   true,   true, false, false, true, true, true]

  def initialize
    @verbose = true
  end

  def parse(args)
    # was: /#{args[0]}/i if args[0]
    # currently can be a filename, or a pattern. the pattern is assumed to be living in product/views,reports
    # Note: views and reports are now in separate repos (manageiq and manageiq-ui-classic)
    @pattern = args[0]
    self
  end

  def filenames
    if pattern
      if Dir.exist?(pattern)
        self.pattern = "#{pattern}/" unless pattern.ends_with?("/")
        Dir["#{pattern}**/*.{yaml,yml}"]
      elsif File.exist?(pattern)
        Dir[pattern]
      else
        pattern_re = /#{pattern}/i
        Dir["product/{views,reports}/**/*.{yaml,yml}"].select { |f| f =~ pattern_re }
      end
    else
      Dir["product/{views,reports}/**/*.{yaml,yml}"]
    end
  end

  # Some report files are of a different form. convert them to a basic hash
  #
  # - MiqReport:
  #   title: Copy of Chargeback - Test SL
  #
  def parse_file(filename)
    return filename if filename.kind_of?(MiqReport)
    data = YAML.load_file(filename)
    if data.kind_of?(Array) && data.size == 1 && data.first["MiqReport"]
      data = data.first["MiqReport"]
    end
    MiqReport.new(data)
  end

  # does the filename suggest a db value?
  # if it does not line up - then we will print to let people know
  def guess_class(filename)
    filename.split("/").last.split(".").first.split("-").first.gsub("_","::").split("__").first
  end

  def check_report(filename)
    rpt = parse_file(filename)

    if verbose
      begin
        if filename.kind_of?(MiqReport)
          #puts "", "#{rpt.name}:", ""
        else
          name = filename
          name << " (#{rpt.db})" if rpt.db != guess_class(filename)

          puts "","#{name}:",""
        end

        rpt.db_class # ensure this can be run
        print_details(rpt)
      rescue NameError
       puts "unknown class defined in ':db' field: #{rpt.db}"
      end
    end
  end

  def self.run(argv = ARGV)
    checker = new.parse(argv)
    puts "running #{checker.filenames.size} reports"
    checker.filenames.each { |f| checker.check_report(f) }.size
  end

  def self.run_widgets

  end

  private

  def visible_columns(*row)
    row.each_with_index.select { |col, i| HEADERS_SHOW[i] }.map(&:first)
  end

  # convert "includes" recursive hash to columns
  # TODO: know when it is a virtual association
  def includes_to_cols(model, h, associations = [])
    return [] if h.blank?
    h.flat_map do |table, table_hash|
      next_associations = associations + [table]
      (table_hash["columns"] || []).map { |col| MiqExpression::Field.new(model, next_associations, col) } +
        includes_to_cols(model, table_hash["includes"], next_associations)
    end
  end

  # a, b, c

  def union_hash(primary, extras)
    return {} unless primary.present? && extras.present?
    primary.each_with_object({}) do |(n, v), h|
      if extras[n]
        h[n] = union_hash(v, extras[n])
      end
    end
  end

  def strs_to_fields(model, associations, cols)
    cols.map { |col| MiqExpression::Field.new(model, associations, col) }
  end

  def flds_to_strs(flds)
    flds.map { |f| (f.associations + [f.column]).join(".") }
  end

  # # any includes that look funny?
  # def noteable_includes?(h)
  #   return false if h.blank?
  #   h.each do |table, table_hash|
  #     return true if (table_hash.keys - %w(includes columns)).present?
  #     return true if noteable_includes?(table_hash["includes"])
  #   end
  #   false
  # end

  # reports are typically in product/view/*.yml, this abbreviates that name, and padds to the left
  def short_padded_filename(filename, filenamesize)
    sf = filename.split("/")
    # shorten product/view/rpt.yml text - otherwise, just use the name
    sf = sf.size < 2 ? sf.last : "#{sf[1][0]}/#{sf[2..-1].join("/")}"
    if sf.size > filenamesize
      sf + "\n" + "".ljust(filenamesize)
    else
      sf.ljust(filenamesize)
    end
  end

  def print_details(rpt)
    tbl = Table.new
    tbl.headings = visible_columns(*HEADERS)

    # fields used for find (mostly reports)
    include_for_find = rpt.include_for_find || {}
    # hash representing columns to include
    includes_cols = Set.new(flds_to_strs(includes_to_cols(rpt.db, rpt.include)))

    includes_tbls = rpt.try(:include_as_hash)
    includes_tbls = rpt.invent_includes if rpt.include.blank? # removed from yaml file
    includes_tbls ||= {}

    # columns defined via includes / (joins)  
    rpt_cols = Set.new(rpt.cols)
    sort_cols = Set.new(Array.wrap(rpt.sortby))
    if (miq_cols = rpt.conditions.try(:fields))
      # use fully qualified field names
      cond_cols = Set.new(miq_cols.map { |c| ((c.associations||[]) + [c.column]).compact.join(".") })
      #miq_cols = miq_cols.index_by { |c| c.column }
    else
      cond_cols = Set.new
    end

    if (miq_cols = rpt.display_filter.try(:fields))
      # use fully qualified field names
      display_cols = Set.new(miq_cols.map { |c| ((c.associations||[]) + [c.column]).compact.join(".") })
      #miq_cols = miq_cols.index_by { |c| c.column }
    else
      display_cols = Set.new
    end

    # --
    klass = rpt.db_class
    print_cols(tbl, klass, rpt.col_order, "hidden", rpt_cols, includes_cols, rpt.col_order, sort_cols, cond_cols, display_cols)

    # cols brought back in sql but not displayed (present in col_order)
    # they may be used by custom ui logic or a ruby virtual attribute
    # typically this field is unneeded and can be removed
    sql_only = rpt_cols - rpt.col_order
    print_cols(tbl, klass, sql_only, "sql only", rpt_cols, includes_cols, rpt.col_order, sort_cols, cond_cols, display_cols)

    # cols brought back via includes, but not displayed (present in col_order)
    # the field may be used by custom ui logic or a ruby virtual attribute
    # do note, this was based upon the assumption that all includes could be derived from column names
    # this was rolled back - so this may not be completely relevant
    include_only = includes_cols - rpt.col_order
    print_cols(tbl, klass, include_only, "include", rpt_cols, includes_cols, rpt.col_order, sort_cols, cond_cols, display_cols)

    # cols in in_sort, but not defined (and not displayed)
    # Pretty sure the ui ignores this column
    # TODO: not sure what we should highlight here
    sort_only = sort_cols - rpt.col_order - includes_cols - rpt_cols
    print_cols(tbl, klass, sort_only, "sort only", rpt_cols, includes_cols, rpt.col_order, sort_cols, cond_cols, display_cols)

    # for these: need to convert reports to using Field vs target...
    cond_only = cond_cols - rpt.col_order - includes_cols - rpt_cols
    print_cols(tbl, klass, cond_only, "cond only", rpt_cols, includes_cols, rpt.col_order, sort_cols, cond_cols, display_cols)

    tbl.print_all

    # puts "", "includes: #{includes_tbls.inspect}" if includes_tbls.present?
    # this may be going on the assumption that we are removing include when it can be discovered
    # in the sort_order.
    # see https://github.com/ManageIQ/manageiq/pull/13675
    # see last message of https://github.com/ManageIQ/manageiq/pull/13675 (include changes were reverted)
    puts "", "extra includes: #{include_for_find.inspect}" if include_for_find.present?
    unneeded_iff = union_hash(includes_tbls, include_for_find)
    puts "", "unneeded includes_for_find: #{unneeded_iff.inspect}" if unneeded_iff.present?
  end

  def print_cols(tbl, klass, cols, desc, rpt_cols, includes_cols, col_order, sort_cols, cond_cols, display_cols)
    cols.each do |col|
      in_rpt  = rpt_cols.include?(col)
      in_inc  = includes_cols.include?(col)
      in_col  = col_order.include?(col) ? ""     : desc # true
      in_sort = sort_cols.include?(col)     ? "sort" : ""
      in_miq  = (cond_cols.include?(col) ? "cond" : "") +
                (display_cols.include?(col) ? "display" : "")
      print_row(tbl, klass, col, in_rpt, in_inc, in_sort, in_col, in_miq)
    end
  end
  
  def print_row(tbl, klass, col, in_rpt, in_inc, in_sort, in_col, in_miq)
    *class_names, col_name = [klass.name] + col.split(".")
    field_name = "#{class_names.join(".")}-#{col_name}"

    f = MiqExpression.parse_field_or_tag(field_name)
    is_alias = col.include?(".") ? "alias" : nil
    col_src = in_rpt ? (in_inc ? "both" : "col") : (in_inc ? "includes" : "missing")

    STDERR.puts "problem houston: #{klass}...#{col} (#{field_name})" if f.nil?

    # 1
    vr = nil
      # if f.kind_of?(MiqExpression::Tag)
      #   "custom"
      # elsif f.associations.blank?
      #   "" # "direct"
      # elsif f.virtual_reflection?
      #   "virtual"
      # else
      #   "db"
      # end
    # 2
      va = 
        if f.kind_of?(MiqExpression::Tag)
          "custom"
        elsif f.virtual_reflection?
          "join"
        elsif f.virtual_attribute? #klass && klass.virtual_attribute?(col)
          "attr"
        else
          if klass && (f.target.has_attribute?(f.column) || f.target.try(:attribute_alias?, f.column))
            # these are both good - no reason to call them out
            "" # f.associations.present? ? "join" : "db"
          else
            "unknown"
          end
        end

    # 3
    # tags don't have attribute_supported_by_sql?
    sql_support = klass ? f.try(:attribute_supported_by_sql?) ? "sql" : "ruby" : "?"

    tbl << visible_columns(col, vr, va, sql_support, col_src, is_alias, in_sort, in_col, in_miq)
  end
end
