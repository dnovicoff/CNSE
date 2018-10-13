ITSM Report
==================
Creates an Excel Spreadsheet containing aggregated results from all Linux servers in ITSM. Runs by reading a CSV export from ITSM and logging into each server specified in the CSV.

System Requirements
-------------------
The following are requirements to run this program:

- Perl 5 environment with the following modules:
  - JSON
  - Storable
  - Text::CSV
  - IPC::Open3
  - IO::Socket::INET
  - Net::Ping::External
  - Excel::Writer::XLSX
  - Getopt::Long
- A POSIX compatible runtime environment (RHEL, CentOS, Cygwin, etc).
- A working Chef workstation.
- A CSV export of data from NYS ITSM (Service Now).
- OpenSSH client with a configured SSH key, without a password.
- Valid SSH logins on each server you're testing against, with your SSH key.
- Valid SSH logins on all of the management servers, with your SSH key.

How to Use
-------------------
Export list of server data from NYS ITSM (Service Now) in CSV format with the following columns (in order):

- svr_name
- svr_sys_class_name
- svr_os
- svr_support_group
- svr_short_description
- ip_name
- ip_u_ip_type
- svr_u_owner_department
- svr_u_billing_department
- svr_u_patch_level
- svr_location
- svr_u_type
- svr_start_date

Place file in the same directory as the perl script.  The filename of the CSV export should be named `u_cmdb_ci_server_ip_app_inst.csv`.  Afterwards you can run the `generate-itsm-report.pl` program to run the program.  This should generate an Excel spreadsheet named `Linux-Servers-ITSM-Data.xlsx`.

Optionally, you can specify the parameter `--dry-run` to test your program without logging onto each server in the spreadsheet.  Note that this will still log into the management servers to grab some data.
