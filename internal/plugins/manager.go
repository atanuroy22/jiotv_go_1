package plugins

import (
	"github.com/gofiber/fiber/v2"
	"github.com/jiotv-go/jiotv_go/v3/internal/config"
	"github.com/jiotv-go/jiotv_go/v3/pkg/television"
	"github.com/jiotv-go/jiotv_go/v3/pkg/utils"
)

var activePlugins []func() []television.Channel

func Init(app *fiber.App) {
	for _, plugin := range config.Cfg.Plugins {
		switch plugin {
		default:
			utils.Log.Println("Plugin " + plugin + " not found")
		}
	}
}

func GetChannels() []television.Channel {
	var channels []television.Channel
	for _, generator := range activePlugins {
		channels = append(channels, generator()...)
	}
	return channels
}
