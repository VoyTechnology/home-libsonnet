// A minimal mixin: just fields, no dependency on the library.
{
  homeassistantAutomations+:: {
    porch_light: {
      alias: 'Porch light at sunset',
      triggers: [{ trigger: 'sun', event: 'sunset' }],
      actions: [{ action: 'light.turn_on', target: { entity_id: 'light.porch' } }],
    },
  },
  homeassistantScripts+:: {
    goodnight: {
      alias: 'Goodnight',
      sequence: [{ action: 'light.turn_off', target: { area_id: 'living_room' } }],
    },
  },
  homeassistantScenes+:: {
    movie: [{ name: 'Movie', entities: { 'light.living_room': { state: 'off' } } }],
  },
  homeassistantDashboards+:: {
    energy_overview: {
      title: 'Energy',
      icon:: 'mdi:flash',
      views: [{ title: 'Overview', cards: [] }],
    },
  },
}
