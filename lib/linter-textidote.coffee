{CompositeDisposable} = require 'atom'
fs = require 'fs'
path = require 'path'
helpers = require 'atom-linter'
XRegExp = require('xregexp').XRegExp

xcache = new Map

module.exports =
  config:
    executablePath:
      type: 'string'
      default: "/usr/local/bin/textidote"
      description: 'Path to the textidote binary'
    textidoteArguments:
      type: 'array'
      default: ["--check", "en"]
      description: 'Arguments to pass to textidote. Seperate by comma.'

  activate: (state) ->
    require("atom-package-deps").install("linter-textidote")
      .then ->
        console.log 'linter-textidote loaded'
        @subscriptions = new CompositeDisposable
        @subscriptions.add atom.config.observe 'linter-textidote.executablePath',
          (executablePath) =>
            # console.log 'observe ' + executablePath
            @executablePath = executablePath
        @subscriptions.add atom.config.observe 'linter-textidote.textidoteArguments',
          (textidoteArguments) =>
            # console.log 'observe ' + textidoteArguments
            @textidoteArguments = textidoteArguments

  deactivate: ->
    @subscriptions.dispose()

  provideLinter: ->
    provider =
      name: 'textidote'
      grammarScopes: ['text.tex.latex', 'text.tex.latex.beamer', 'text.tex.latex.memoir', 'text.tex.latex.knitr']
      scope: 'file'
      lintsOnChange: false
      lint: (textEditor) =>
          if fs.existsSync(textEditor.getPath())
            return @lintFile textEditor.getPath()
              .then @parseOutput
          console.log 'file "' + textEditor.getPath() + '"" does not exist'
          return []

  lintFile: (filePath) ->
    args = ["--output", "singleline", "--read-all", "--no-color", "--no-config"]
    if textidoteArguments
      for x in textidoteArguments
        args.push x
    args.push filePath
    # console.log args.join(" ")
    opt = {}
    opt.uniqueKey = 'textidote'
    opt.stream =  'both'
    console.log "linting: " + filePath
    return helpers.exec(executablePath, args, opt)

  parseOutput: (output, filePath) ->
    console.log "linting finished: " + filePath + "\n" + output.stderr
    rawRegex = '^(?<file>.+)\\(L(?<lineStart>[0-9]+)C(?<colStart>[0-9]+)-L(?<lineEnd>[0-9]+)C(?<colEnd>[0-9]+)\\): (?<message>.+) Suggestions: \\[(?<suggestions>.+)\\].*$'
    toReturn = []
    if xcache.has(rawRegex)
      regex = xcache.get(rawRegex)
    else
      xcache.set(rawRegex, regex = XRegExp(rawRegex, 'm'))
    #for line in output.split(/\r?\n/)
    for line in output.stdout.split('\n')
      # console.log line
      match = XRegExp.exec(line, regex)
      if match
        # console.log match
        lineStart = parseInt(match.lineStart,10) - 1
        colStart = parseInt(match.colStart,10) - 1
        lineEnd = parseInt(match.lineEnd,10) - 1
        colEnd = parseInt(match.colEnd,10) - 1
        range = [[lineStart, colStart], [lineEnd, colEnd]]
        message = match.message

        solutions = []
        for suggestion in match.suggestions.split(', ')
          solutions.push {position: range, title: 'Change to: ' + suggestion, replaceWith: suggestion}

        # console.log solutions

        toReturn.push({
          severity: "warning",
          location: {
            file: match.file,
            position: range
          },
          solutions: solutions,
          description: message,
          excerpt: message
        })
      # console.log toReturn
    return toReturn
