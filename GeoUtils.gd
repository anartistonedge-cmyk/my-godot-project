extends Node

var CENTER_LAT
var CENTER_LON
var METERS_PER_DEGREE
var SCALE

func convert_coords(lat, lon):

	var x = (lon - CENTER_LON) * METERS_PER_DEGREE * cos(CENTER_LAT * PI / 180.0)
	var z = (lat - CENTER_LAT) * METERS_PER_DEGREE

	return Vector3(x * SCALE, 0, -z * SCALE)
