# gitrab-project-exporter
Exporting Gitlab projects.

Exports all projects that can be viewed by the user specified by access_token.
It is also possible to filter by group name.

## Installation
Execute the bundle install.
```sh
$ bundle install
```

Set api endpoint and access token.
```sh
$ vi config.yml
```

```yaml
---
:api_endpoint: 'http://HOSTNAME/api/v4'
:access_token: 'YOUR ACCESS TOKEN'
```

## Usage
Usage examples:

```sh
$ bundle exec ruby gitlab-project-exporter.rb
```

## Usage（Filter by Group Name）

```sh
$ bundle exec ruby gitlab-project-exporter.rb -g "Group Name"
```

## Usage（Set output directory）

```sh
$ bundle exec ruby gitlab-project-exporter.rb -o "/tmp/"
```
