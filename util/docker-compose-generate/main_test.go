package main

import (
	"bytes"
	"io/ioutil"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_runTemplate(t *testing.T) {
	testRoot := "tests"

	tests, err := ioutil.ReadDir(testRoot)
	if err != nil {
		panic(err)
	}

	for _, test := range tests {
		if !test.IsDir() {
			continue
		}

		t.Run(test.Name(), func(t *testing.T) {
			req := require.New(t)

			config, err := loadConfig(filepath.Join(testRoot, test.Name(), "config.json"))
			req.NoError(err)

			expected, err := ioutil.ReadFile(filepath.Join(testRoot, test.Name(), "expected.yaml"))
			req.NoError(err)

			var actual bytes.Buffer
			err = runTemplate([]byte(DockerComposeTemplate), config, &actual)
			req.NoError(err)

			assert.Equal(t, string(actual.Bytes()), string(expected))
		})
	}
}
