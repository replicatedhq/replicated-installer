package main

// Implementation of docker-compose-generate.sh to run on our servers in order to avoid running bash scripts with injectable parameters

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"text/template"

	"github.com/blang/semver"
	"github.com/pkg/errors"
)

//go:embed docker-compose.tmpl
var DockerComposeTemplate string

type CmdArgs struct {
	ConfigFilename string
	TemplateParams map[string]interface{}
}

func main() {
	printRaw := flag.Bool("raw", false, "print untemplated config to stdout")
	configFilename := flag.String("config", "", "config file name")
	flag.Parse()

	if printRaw != nil && *printRaw {
		fmt.Fprint(os.Stdout, DockerComposeTemplate)
		os.Exit(0)
	}

	if configFilename == nil || *configFilename == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	config, err := loadConfig(*configFilename)
	if err != nil {
		panic(err)
	}

	templateData, err := ioutil.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}

	err = runTemplate(templateData, config, os.Stdout)
	if err != nil {
		panic(err)
	}
}

func loadConfig(filename string) (map[string]interface{}, error) {
	configData, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, errors.Wrap(err, "read config file")
	}

	config := map[string]interface{}{}
	err = json.Unmarshal(configData, &config)
	if err != nil {
		return nil, errors.Wrap(err, "read parse config data")
	}

	return config, nil
}

func runTemplate(templateData []byte, config map[string]interface{}, w io.Writer) error {
	funcMap := template.FuncMap{
		"isSet":                       isSet,
		"getReplicatedRegistryPrefix": getReplicatedRegistryPrefix,
	}

	parsedTemplate, err := template.New("compose").Delims("repl[[", "]]").Funcs(funcMap).Parse(string(templateData))
	if err != nil {
		return errors.Wrap(err, "parse template")
	}

	err = parsedTemplate.Execute(w, config)
	if err != nil {
		return errors.Wrap(err, "execute template")
	}

	return nil
}

// Template helpers

func isSet(m map[string]interface{}, key string) bool {
	val, ok := m[key]
	if !ok {
		return false
	}

	if val == nil {
		return false
	}

	if val, ok := val.(string); ok {
		return val != ""
	}

	return true
}

var replicated2450 = semver.MustParse("2.45.0")

func getReplicatedRegistryPrefix(versionString string) string {
	prefix := "replicated"

	version, err := semver.ParseTolerant(versionString)
	if err != nil {
		return prefix
	}

	if version.LT(replicated2450) {
		prefix = "quay.io/replicated"
	}

	return prefix
}
