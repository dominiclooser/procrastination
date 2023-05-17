time = require 'time-grunt'
jit = require 'jit-grunt'
autoprefixer = require 'autoprefixer'
fs = require 'fs'
glob = require 'glob'
toml = require 'toml'
pug = require 'pug'
replaceExt = require 'replace-ext'
{ join, parse } = require 'path'
path = require 'path'
_ = require 'lodash'
yaml = require 'yaml'
matter = require 'gray-matter'
rimraf = require 'rimraf'
marked = require 'marked'
moment = require 'moment-timezone'
imageminMozjpeg = require 'imagemin-mozjpeg'
imageminPngquant = require 'imagemin-pngquant'
Cite = require 'citation-js'

LOCAL_DATA_DIR = 'data'
PROCESSED_DATA_DIR = '.temp/data'
OUT_DIR = 'out'
HEY_CONFIG_PATH = 'config.yml'
PAGES_PATH = 'dynamic/pages'

try
    configString = fs.readFileSync(HEY_CONFIG_PATH, 'utf8')
    HEY_CONFIG = yaml.parse(configString)

getFileData = (dataPath) ->
    name = parse(dataPath).base
    id = replaceExt(name, '')
    suffix = parse(dataPath).ext
    try
        content = fs.readFileSync(dataPath, 'utf8')
    catch error
        console.log('could not read ' + dataPath)
        throw error
    data = {}

    if suffix == '.md'
        parsed = matter(content)
        data = parsed.data
        data.content = marked(parsed.content)
    
    else if suffix == '.yml'
        try
            data = yaml.parse(content)
        catch error
            console.log(error)

    else if suffix == '.toml'
        try
            data = toml.parse(content)
        catch error
            console.log(error)

    else if suffix == '.bib'
        try
            data = Cite(content).format('data', {format: 'object'})
        catch error
            console.log(error)
    
    if data
        data.id = id
    return data

getDataObject = (dir) ->
    data = {}
    
    for name in fs.readdirSync(dir)
        if name.startsWith('_')
            # console.debug('skipping ' + name)
            continue
        dataPath = join(dir, name)
        id = replaceExt(name, '')
        # id = id.split('-').join('_')
        if fs.lstatSync(dataPath).isDirectory()
            # list = []
            # for name in fs.readdirSync(dataPath)
            #     filePath = join(dataPath, name)
            #     if name.startsWith('_')
            #         continue
            #     else if fs.lstatSync(filePath).isDirectory()
            #         continue
            #     else
            #         fileData = getFileData(filePath)
            #         list.push(fileData)
            # data[id] = list

            try
                data[id] = getDataObject(dataPath)
            catch e
                console.error(e)
        else
            try
                data[id] = getFileData(dataPath)
            catch e
                console.log(e)
    return data

getDefaultPugOptions = () ->
    
    getImages = (dirId) -> 
        answer = []
        baseDir = 'dynamic/images/' + dirId
        if fs.existsSync(baseDir)
            for name in fs.readdirSync(baseDir)
                ext = path.parse(name).ext
                if ext in ['.jpg', '.png']
                    fileId = dirId + '/' + name
                    answer.push(fileId)
        return answer
    
    containsImages = (dirId) ->
        images = getImages(dirId)
        if images.length == 0
            return false
        else
            return true

    toWidth = (size) ->
        if size == 's'
            return 400
        else if size == 'm'
            return 1000
        else if size == 'l'
            return 1500
        else
            throw 'undefined image size'
    
    read = (filename) ->

        if fs.existsSync(filename)
            return fs.readFileSync(filename)
        else
            return ''  

    bibtexToObject = (filepath) ->
        content = fs.readFileSync(filepath)
        data = Cite(content).format('data', {format: 'object'})
        return data  

    wikidata = {} # todo

    marked.setOptions
        smartypants: true

    options =
        basedir: 'dynamic/shared'
        global: getDataObject(LOCAL_DATA_DIR)
        base: (path) -> parse(path).base
        parse: parse
        fs: fs
        moment: moment
        getImages: getImages
        containsImages: containsImages
        marked: marked
        toWidth: toWidth
        plugins: [{read: read}]
        wikidata: wikidata
        join: join
        Cite: Cite

    if HEY_CONFIG?.external
        options.external = getDataObject(HEY_CONFIG.external)
    
    # console.log(getDataObject(HEY_CONFIG.external))

    return options

generatePagesFromData = () ->
    if not HEY_CONFIG
        return
        
    for generator in HEY_CONFIG.generators
            
        targetDirName = generator.target || ''
        targetRoot = join(OUT_DIR, targetDirName)
        if !fs.existsSync(targetRoot)
            fs.mkdirSync(targetRoot)

        templateName = generator.template || 'page.pug'

        templatePath = 'dynamic/shared/' + templateName
        templateString = fs.readFileSync(templatePath)
        parsedTemplate = matter(templateString)
        templateContent = parsedTemplate.content
        templateData = parsedTemplate.data
        
        dataConfig = generator.data
        splitted = dataConfig.split(':')
        if splitted.length == 2 and splitted[0] == 'external'
            dataDir = HEY_CONFIG['external']
            dataGlob = splitted[1]
        else
            dataDir = LOCAL_DATA_DIR
            dataGlob = dataConfig

        for dataPath in glob.sync(join(dataDir, dataGlob))
            if parse(dataPath).name.startsWith('_')
                continue
            local = {}
            _.merge(local, getFileData(dataPath), templateData)

            options = getDefaultPugOptions()
            options.local = local
            
            process.stdout.write("Rendering #{templatePath} with data from #{dataPath} ... ")
            try
                html = pug.render(templateContent, options)
            catch e
                console.log('error.')
                console.error(e)
                continue
                
            key = parse(dataPath).base
            name = replaceExt(key, '.html')
            if local.path
                targetDir = join(targetRoot, local.path)
                if !fs.existsSync(targetDir)
                    fs.mkdirSync(targetDir)
                targetFile =  join(targetDir, 'index.html')
            else
                targetFile = join(targetRoot, name)
        
            fs.writeFileSync(targetFile, html)
            console.log("done. Generated #{targetFile}")

buildPage = (pageName) ->
    pagePath = join(PAGES_PATH, "#{pageName}.pug")
    string = fs.readFileSync(pagePath)
    parsed = matter(string)
    options = getDefaultPugOptions()
    options.local = parsed.data
    options.path = pageName
    pugString = parsed.content
    
    try
        process.stdout.write("Compiling #{pagePath} ... ")
        html = pug.render(pugString, options)
    catch e
        console.log('error.')
        console.error(e)

    relativeTarget = replaceExt(pageName, '.html')
    target = join(OUT_DIR, relativeTarget)
    console.log("done. Writing to #{target}")
    fs.writeFileSync(target, html)

buildSinglePages = () ->
   
    for pagePath in glob.sync('dynamic/pages/**/*.pug')
        if parse(pagePath).name.startsWith('_')
            continue
        relativePath = path.relative(PAGES_PATH, pagePath)
        urlPath = replaceExt(relativePath, '')
        string = fs.readFileSync(pagePath)
        parsed = matter(string)
        options = getDefaultPugOptions()
        options.local = parsed.data
        options.path = urlPath
        pugString = parsed.content
        
        try
            process.stdout.write("Compiling #{pagePath} ... ")
            html = pug.render(pugString, options)
        catch e
            console.log('error.')
            console.error(e)
            continue

        relativeTarget = replaceExt(relativePath, '.html')
        target = join(OUT_DIR, relativeTarget)
        console.log("done. Writing to #{target}")
        fs.writeFileSync(target, html)

gruntConfig =

    # exec:
    #     encrypt:  'staticrypt out/articles/corona/index.html keinpasswort -o out/articles/corona/index.html'
    #     encrypt2: 'staticrypt out/projects/percy/index.html percy -o out/projects/percy/index.html'
    
    imagemin:
        main: 
            options:
                use: [imageminMozjpeg(), imageminPngquant()]
            files: [
                expand: true
                cwd: 'dynamic/images'
                src: '**/*.{png,jpg,gif}'
                dest: '.temp/images'
            ]

    responsive_images:
        options:
            newFilesOnly: true
            # createNoScaledImage: true
        's':
            options:
                sizes: [{rename: false, width: 400}]
            files: [
                expand: true
                cwd: '.temp/images'
                src: '**/*.{jpg,png,gif}'
                dest: 'out/images/s'
            ]
        'm':
            options:
                sizes: [{rename: false, width: 1000}]
            files: [
                expand: true
                cwd: '.temp/images'
                src: '**/*.{jpg,png,gif}'
                dest: 'out/images/m'
            ]
        'l':
            options:
                sizes: [{rename: false, width: 1500}]
            files: [
                expand: true
                cwd: '.temp/images'
                src: '**/*.{jpg,png,gif}'
                dest: 'out/images/l'
            ]

    'gh-pages':
        production:
            options:
                base: 'out'
            src: '**/*'
        stage:
            options:
                base: 'out'
                repo: 'git@github.com:dominiclooser/dominiclooser.ch-stage.git'
            src: '**/*'
    
    postcss:
        options:
            processors: [autoprefixer()]
        main:
            src: 'out/styles/styles.css'
    
    copy:
        static:
            cwd: 'static'
            src: '**/*'
            expand: true
            dest: 'out' 
        'production':
            src: 'cnames/production'
            dest: 'out/CNAME'
        'stage':
            src: 'cnames/stage'
            dest: 'out/CNAME'
    coffee:
        main:
            expand: true
            flatten: true
            ext: '.js'
            src: 'dynamic/scripts/*.coffee'
            dest: 'out/scripts/'
    stylus:
        main:
            src: 'dynamic/styles/styles.styl'
            dest: 'out/styles/styles.css'  
    watch:
        gruntfile:
            files: 'gruntfile.coffee'
            tasks: 'build'
        scripts:
            files: 'dynamic/scripts/*'
            tasks: 'coffee'
        data:
            files: ['data/**/*', '~/code/data/mydata/**/*']
            tasks: ['pug', 'strip-extensions']
        pages:
            files: ['dynamic/pages/**/*', 'dynamic/shared/**/*']
            tasks: ['pug', 'strip-extensions']
        styles:
            files: 'dynamic/styles/*'
            tasks: 'stylus'
        static:
            files: 'static/**/*'
            tasks: 'copy:static'
        images:
            files: 'dynamic/images/**/*'
            tasks: ['imagemin', 'responsive_images']

module.exports = (grunt) ->
    grunt.initConfig gruntConfig
    time grunt
    jit grunt

    grunt.registerTask 'print-data', ->
        console.log getDataObject(LOCAL_DATA_DIR)

    grunt.registerTask 'clean', -> 
        rimraf.sync(join(OUT_DIR, '*'))

    grunt.registerTask 'clean-data', ->
        rimraf.sync(PROCESSED_DATA_DIR)

    grunt.registerTask 'make-dirs', ->
        if !fs.existsSync(OUT_DIR)
            fs.mkdirSync(OUT_DIR)
        for name in fs.readdirSync(PAGES_PATH)
            if fs.lstatSync(path.join(PAGES_PATH, name)).isDirectory()
                outSubdir = path.join(OUT_DIR, name)
                if ! fs.existsSync(outSubdir)
                    fs.mkdirSync(outSubdir)

    grunt.registerTask 'strip-extensions', ->
        for filePath in glob.sync('out/**/*.html')
            parsedPath = parse(filePath)
            name = parsedPath.name
            if name != 'index'
                dir = parsedPath.dir
                newDir = dir + '/' + name
                if !fs.existsSync(newDir)
                    fs.mkdirSync(newDir)
                fs.renameSync(filePath, newDir + '/index.html')
    
    grunt.registerTask 'page', (pagePath) ->
        buildPage(pagePath)

    grunt.registerTask 'pug', ->
        generatePagesFromData()
        buildSinglePages()

    grunt.registerTask 'build', ['make-dirs', 'pug', 'stylus', 'postcss', 'coffee', 'copy:static', 'strip-extensions']
    grunt.registerTask 'default', ['build', 'watch']
    
    grunt.registerTask 'full_build', ['clean', 'make-dirs', 'imagemin', 'responsive_images', 'build'] 
    
    grunt.registerTask 'deploy', ['clean', 'make-dirs', 'build', 'copy:production', 'gh-pages:production']
    grunt.registerTask 'stage', ['clean-build','copy:stage', 'gh-pages:stage']