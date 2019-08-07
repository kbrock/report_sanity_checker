require_relative "report_sanity_checker/version"
require_relative "report_sanity_checker/table"

class ReportSanityChecker
  attr_accessor :patterns
  # report with column information
  attr_accessor :column_report
  # run each report to ensure it works
  attr_accessor :run_it
  # print sql for each report
  attr_accessor :print_sql

  attr_accessor :columns

  #                 0      1        2       3     4      5      6    7      8
  HEADERS      = %w(column relation virtual sql   src    alias  sort hidden cond)
  HEADERS_SHOW =   [true,  false,   true,   true, false, false, true, true, true]

  def initialize
    @column_report = true
    @run_it = false
    @print_sql = false
  end

  def parse(args)
    # Note: views and reports are now in separate repos (manageiq and manageiq-ui-classic)
    ActiveRecord::Base.logger = Logger.new(STDOUT) if args.delete("-v")
    @run_it = args.delete("--run")
    @print_sql = args.delete("--sql")
    @patterns = args
    self
  end

  def filenames
    return Dir["product/{views,reports}/**/*.{yaml,yml}"] if patterns.empty?

    patterns.flat_map do |pattern|
      if Dir.exist?(pattern)
        pattern = "#{pattern}/" unless pattern.ends_with?("/")
        Dir["#{pattern}**/*.{yaml,yml}"]
      elsif File.exist?(pattern)
        pattern
      else
        pattern_re = /#{pattern}/i
        Dir["product/{views,reports}/**/*.{yaml,yml}"].select { |f| f =~ pattern_re }
      end
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

    if column_report
      if filename.kind_of?(MiqReport)
        #puts "", "#{rpt.name}:", ""
      else
        name = filename
        name = "#{name} (#{rpt.db})" if rpt.db != guess_class(filename)

        puts "","#{name}:",""
      end
      begin
        rpt.db_class # ensure this can be run
      rescue NameError
        puts "unknown class defined in ':db' field: #{rpt.db}"
      end
      print_details(rpt)
    end
    run_report(rpt)
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

    includes_available = rpt.include.present?
    # what includes are in the report file (and col's virtual attributes)
    includes_declared  = rpt.include_as_hash
    # what includes would be invented from col_sort
    includes_generated = rpt.invent_includes
    # what includes would be used by the sort (via :include or :col_sort) + include_for_find merged in)
    full_includes_tbls = rpt.get_include_for_find
    # full_includes without include_for_find merged in
    includes_tbls = includes_available ? includes_declared : includes_generated

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

    # see https://github.com/ManageIQ/manageiq/pull/13675
    # see last message of https://github.com/ManageIQ/manageiq/pull/13675 (include changes were reverted)
    if includes_available
      # include_for_find can make up for missing entries in includes_declared - merging it
      sm_includes = union_hash(includes_declared, includes_generated)
      declared_v_generated_includes = union_hash(includes_declared, includes_generated.deep_merge(include_for_find))
      if declared_v_generated_includes == includes_declared
        puts "", "unneeded 'includes:' block (this is only accurate as of I release)"
      else
        puts "", "includes declared: #{includes_declared}"
        puts "includes generated: #{includes_generated}"
      end
    elsif rpt.include
      puts "", "unneeded blank includes block"
    end
    # these are not needed for the query (may be needed for the screen or ruby attributes)
    puts "", "extra includes: #{include_for_find.inspect}" if include_for_find.present?
    # these are already generated, not needed to add them
    unneeded_iff = union_hash(includes_tbls, include_for_find)
    puts "", "unneeded includes_for_find: #{unneeded_iff.inspect}" if unneeded_iff.present?
    puts "includes: #{full_includes_tbls}"
    # invalid entries
    trace_includes(klass, full_includes_tbls) if full_includes_tbls
  rescue NameError => e
    puts "not able to fetch class: #{e.message}"
  end

  def run_report(rpt, options = {})
    return unless print_sql || run_it

    # rpt.generate_table(:user => User.super_admin)
    count, timing = User.with_user(User.super_admin) do
      rslt = _generate_table(rpt, options)
      puts "sql", (rslt.to_sql rescue "sql issues") if print_sql
      if run_it
        start = Time.now
        sz = rslt.to_a.size
        [sz, Time.now - start]
      else
        [0, 0]
      end
    end

    fmt_time = Time.at(timing).utc.strftime("%H:%M:%S:%U")
    puts "", "report ran with #{count} rows in #{fmt_time}ms" if run_it
  rescue => e
    puts "", "could not run report", e.message
    puts e.backtrace
  end

  def _generate_table(rpt, options = {})
    #return build_table_from_report(rpt, options) if rpt.db == rpt.class.name # Build table based on data from passed in report object
    raise "table_from_report not supported" if rpt.db == rpt.class.name # Build table based on data from passed in report object
    rpt.send(:_generate_table_prep)

    results = if rpt.send(:custom_results_method)
                rpt.generate_custom_method_results(options)
              elsif rpt.performance
                rpt.generate_performance_results(options)
              elsif rpt.send(:interval) == 'daily' && rpt.send(:db_klass) <= MetricRollup
                rpt.generate_daily_metric_rollup_results(options)
              elsif rpt.send(:interval)
                rpt.generate_interval_metric_results(options)
              else
                rpt.generate_basic_results(options)
              end
    results
  end

  def print_cols(tbl, klass, cols, desc, rpt_cols, includes_cols, col_order, sort_cols, cond_cols, display_cols)
    cols.each do |col|
      in_rpt  = rpt_cols.include?(col)
      in_inc  = includes_cols.include?(col)
      in_col  = col_order.include?(col) ? ""     : desc # true
      in_sort = sort_cols.include?(col)     ? "sort" : ""
      in_miq  = [cond_cols.include?(col) ? "cond" : nil, display_cols.include?(col) ? "display" : nil].compact.join(" ")
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

  def trace_includes(klass, includes)
    klass_reflections = klass.reflections
    includes.each do |k, v|
      if relation = klass_reflections[k.to_s]
        trace_includes(relation.klass, v) if includes.present? # and relation not polymorphic
      elsif klass.virtual_attribute?(k)
      elsif klass.virtual_reflection?(k)
      else
        puts "unknown includes: #{klass.name}.#{k}"
      end
    end
  end
end
