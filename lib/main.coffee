{CompositeDisposable} = require 'atom'
{find} = helpers = require 'atom-linter'
path = require 'path'
globule = require 'globule'

module.exports =
  config:
    noConfigDisable:
      title: 'Disable when no sass-lint config file is found in your project and a .sass-lint.yml file is not specified in the .sass-lint.yml Path option'
      type: 'boolean'
      default: false
    configPath:
      title: '.sass-lint.yml Path'
      description: 'A .sass-lint.yml file to use/fallback to if no config file is found in the current project root'
      type: 'string'
      default: ''
    executablePath:
      title: 'sass-lint package Path'
      description: 'If you\'d like to use a copy of sass-lint other than the one included with this package, specify the path to it here e.g. \'/Users/username/packages/sass-lint\''
      type: 'string'
      default: path.join(__dirname, '..', 'node_modules', 'sass-lint')

  getFilePath: (path) ->
    relative = atom.project.relativizePath(path)

  activate: ->
    require('atom-package-deps').install()
    @subs = new CompositeDisposable
    @subs.add atom.config.observe 'linter-sass-lint.noConfigDisable',
      (noConfigDisable) =>
        @noConfigDisable = noConfigDisable
    @subs.add atom.config.observe 'linter-sass-lint.configPath',
      (configPath) =>
        @configPath = configPath
    @subs.add atom.config.observe 'linter-sass-lint.executablePath',
      (executablePath) =>
        @executablePath = executablePath

  deactivate: ->
    @subs.dispose()

  provideLinter: ->
    provider =
      name: 'sass-lint'
      grammarScopes: ['source.css.scss', 'source.scss', 'source.css.sass', 'source.sass']
      scope: 'file'
      lintOnFly: true
      lint: (editor) =>
        configExt = '.sass-lint.yml'
        filePath = editor.getPath()
        projectConfig = find filePath, configExt
        globalConfig = if @configPath is '' then null else @configPath
        config = if projectConfig isnt null then projectConfig else globalConfig

        try
          linter = require(@executablePath)
        catch error
          atom.notifications.addWarning """
            **Sass-lint package missing**

            The sass-lint package cannot be found, please check sass-lint package path option of this package. \n
            If you leave this option empty the sass-lint package included with linter-sass-lint will be used.
          """
          return []

        if config isnt null and path.extname(config) isnt '.yml'
          config = path.join @configPath, configExt
          atom.notifications.addWarning """
            **Deprecation Warning**

            As of `1.0.0` the configPath option will require you to
            explicitly specify a .sass-lint.yml file rather than just a path to search.

            Please add the full path and filename to this plugins configPath option.
          """

        if config is null and @noConfigDisable is false
          atom.notifications.addError """
            **No .sass-lint.yml config file found.** You can find an example of one
            [here](https://github.com/sasstools/sass-lint/blob/master/lib/config/sass-lint.yml)
            and documentation on how to configure this and each of the rules
            [here](https://github.com/sasstools/sass-lint/tree/master/docs).
          """

          return []

        else if config is null and @noConfigDisable is true
          return []

        try
          compiledConfig = linter.getConfig({}, config)

          if globule.isMatch(compiledConfig.files.include, this.getFilePath(filePath)[1]) and not globule.isMatch(compiledConfig.files.ignore, this.getFilePath(filePath)[1])
            result = linter.lintText({
              text: editor.getText(),
              format: path.extname(filePath).slice(1),
              filename: filePath
            }, {}, config)
        catch error
          messages = []
          match = error.message.match /Parsing error at [^:]+: (.*) starting from line #(\d+)/
          if match
            text = "Parsing error: #{match[1]}."
            lineIdx = Number(match[2]) - 1
            line = editor.lineTextForBufferRow(lineIdx)
            colEndIdx = if line then line.length else 1

            return [
              type: 'Error'
              text: text
              filePath: filePath
              range: [[lineIdx, 0], [lineIdx, colEndIdx]]
            ]
          else
            atom.notifications.addError """
              **sass-lint had a problem**
              Please consider filing an issue with [linter-sass-lint](https://github.com/AtomLinter/linter-sass-lint)
              or [sass-lint](https://github.com/sasstools/sass-lint) including the text below and any other
              information possible.

              #{error.stack}
            """, {dismissable: true}
          return []

        if result then return result.messages.map (msg) ->
          line = if msg.line then msg.line - 1 else 0
          col = if msg.column then msg.column - 1 else 0
          text = if msg.message then ' ' + msg.message else 'Unknown Error'
          html = '<span class="badge badge-flexible">' + msg.ruleId + '</span>' + text

          result = {
            type: if msg.severity is 1 then 'Warning' else if msg.severity is 2 then 'Error' else 'Info',
            html,
            filePath: filePath,
            range: [[line, col], [line, col + 1]]
          }

          return result

        return []
