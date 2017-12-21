# ReportSanityChecker

report_sanity_checker looks at a report, widget, or table view and runs a basic sanity check.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'report_sanity_checker'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install report_sanity_checker

## Usage

```bash
vmdb
report_sanity_checker # reads product/reports
report_sanity_checker ../manageiq-ui-classic/product/views/
report_sanity_checker underutilized.yml
report_sanity_checker -w # widgets
```

## Sample output

```bash
report_sanity_checker.rb underutilized.yml
```

### underutilized.yaml (Vm):

| column                                         | virtual | sql  | sort | hidden    | cond | 
|:-----------------------------------------------|:--------|:-----|:-----|:----------|:-----|
| managed.cust_portfolio                         | custom  | ruby | sort |           |      | 
| managed.cust_owner                             | custom  | ruby |      |           |      | 
| name                                           |         | sql  |      |           |      | 
| created_on                                     |         | sql  |      |           |      | 
| active                                         | attr    | sql  |      |           |      | 
| cpu_total_cores                                | attr    | sql  |      |           |      | 
| overallocated_vcpus_pct                        | attr    | ruby |      |           | cond | 
| cpu_usagemhz_rate_average_max_over_time_period | attr    | sql  |      |           |      | 
| mem_cpu                                        | attr    | sql  |      |           |      | 
| overallocated_mem_pct                          | attr    | ruby |      |           | cond | 
| derived_memory_used_max_over_time_period       | attr    | sql  |      |           |      | 
| allocated_disk_storage                         | attr    | sql  |      |           |      | 
| used_disk_storage                              | attr    | sql  |      |           |      | 
| v_pct_free_disk_space                          | attr    | sql  |      |           | cond | 
| v_pct_used_disk_space                          | attr    | sql  |      |           |      | 


This tells us a few things:

- This report is based upon the `Vm` model (first line)
- `managed.cust_portfolio` is sorting on a tag - this is determined in ruby. sorting in ruby requires all records to be in memory.
- `name` is a regular sql column
- `active` is a virtual attribute but is derived in sql - you can sort or filter on this
- Record filter uses 3 columns. Since `overallocated_vcpus_pct` is determined in ruby, filtering is performed in ruby. All records are brought back from the database.
- `v_pct_free_disk_space` is calculated on the fly, but can be calculated in sql. Filtering on this field does not require all records be loaded into memory. Since the `MiqExpression` has an `OR` for these fields, this optimization can not be used.

Take away:
- A report that only filters by `v_pct_free_disk_space` would be much quicker and wouldn't download every VM into memory.
- the whole `Vm` table is downloaded. This report will run slowly.


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/report_sanity_checker.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
