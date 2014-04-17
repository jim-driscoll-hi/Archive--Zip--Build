Name: perl-Archive-Zip-Build
Version: 0.1.0
Release: 1
License: BSD
Summary: Common libraries with unrestricted internal distribution
Group: Development/Libraries
Packager: Jim Driscoll <jim.driscoll@heartinternet.co.uk>
Source: Archive-Zip-Build-%{version}.tar
BuildArch: noarch
BuildRoot: %{_builddir}/%{name}-%{version}-%{release}

%description
Perl libraries to support building zip files.

%prep
%setup -n Archive-Zip-Build-%{version}

%build

%install
install -d $RPM_BUILD_ROOT/%{perl_vendorlib}/Archive/Zip
install Archive/Zip/*.pm $RPM_BUILD_ROOT/%{perl_vendorlib}/Archive/Zip/

%files
%defattr(-,root,root)
%{perl_vendorlib}/Archive/Zip/*.pm

%changelog
* Thu Apr 17 2014 Jim Driscoll <jim.driscoll@heartinternet.co.uk> 0.1.0-1
- Initial RPM

