///////////////////////////////////////////////////////////////////////////////////
// 
//  Copyright (c) 2014 <nailsonnego@gmail.com>
// 
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
// 
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
// 
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
///////////////////////////////////////////////////////////////////////////////////

package nail.objectbuilder.core
{
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.net.registerClassAlias;
	import flash.utils.ByteArray;
	
	import nail.objectbuilder.commands.CommandType;
	import nail.objectbuilder.commands.ErrorCommand;
	import nail.objectbuilder.commands.MessageCommand;
	import nail.objectbuilder.commands.SetAssetsInfoCommand;
	import nail.objectbuilder.commands.SetSpriteListCommand;
	import nail.objectbuilder.commands.SetThingCommand;
	import nail.otlib.assets.AssetsInfo;
	import nail.otlib.assets.AssetsVersion;
	import nail.otlib.sprites.SpriteStorage;
	import nail.otlib.things.ThingCategory;
	import nail.otlib.things.ThingType;
	import nail.otlib.things.ThingTypeStorage;
	import nail.otlib.utils.ThingUtils;
	import nail.utils.StringUtil;
	import nail.workers.Command;
	import nail.workers.NailWorker;
	
	public class ObjectBuilderWorker extends NailWorker
	{
		//--------------------------------------------------------------------------
		//
		// PROPERTIES
		//
		//--------------------------------------------------------------------------
		
		private var _things : ThingTypeStorage;
		
		private var _sprites : SpriteStorage;
		
		private var _datFile : File;
		
		private var _sprFile : File;
		
		private var _version : AssetsVersion;
		
		//--------------------------------------------------------------------------
		//
		// CONSTRUCTOR
		//
		//--------------------------------------------------------------------------
		
		public function ObjectBuilderWorker()
		{
			
		}
		
		//--------------------------------------------------------------------------
		//
		// METHODS
		//
		//--------------------------------------------------------------------------
		
		//--------------------------------------
		// Override Protected
		//--------------------------------------
		
		override protected function register() : void
		{
			registerClassAlias("ThingType", ThingType);
			registerClassAlias("AssetsInfo", AssetsInfo);
			registerCommand(CommandType.LOAD_ASSETS, onLoadAssets);
			registerCommand(CommandType.GET_ASSETS_INFO, onGetAssetsInfo);
			registerCommand(CommandType.COMPILE_ASSETS, onCompileAssets);
			registerCommand(CommandType.NEW_THING, onNewThing);
			registerCommand(CommandType.GET_THING, onGetThing);
			registerCommand(CommandType.UPDATE_THING, onChangeThing);
			registerCommand(CommandType.EXPORT_THING, onExportThing);
			registerCommand(CommandType.DUPLICATE_THING, onDuplicateThing);
			registerCommand(CommandType.GET_SPRITE_LIST, onGetSpriteList);
			registerCommand(CommandType.REPLACE_SPRITE, onReplaceSprite);
			registerCommand(CommandType.IMPORT_SPRITE, onImportSprite);
		}
		
		//--------------------------------------
		// Private
		//--------------------------------------
		
		private function onLoadAssets(args:Array) : void
		{
			var dat : File;
			var spr : File;
			var version : AssetsVersion;
			
			try
			{
				dat = new File(args[0]);
				spr = new File(args[1]);
				version = AssetsVersion.getVersionByValue(args[2]);
			} 
			catch(error:Error) 
			{
				sendError(error.message, error.getStackTrace(), error.errorID);
				return;
			}
			
			sendCommand(new Command(CommandType.SHOW_PROGRESS_BAR, "Loading"));
			
			_datFile = dat;
			_sprFile = spr;
			_version = version;
			
			if (_things != null)
			{
				_things.removeEventListener(Event.COMPLETE, thingsCompleteHandler);
				_things.removeEventListener(Event.CHANGE, thingsChangeHandler);
				_things.removeEventListener(ProgressEvent.PROGRESS, thingsProgressHandler);
				_things.removeEventListener(ErrorEvent.ERROR, thingsErrorHandler);
				_things = null;
			}
			
			if (_sprites != null)
			{
				_sprites.removeEventListener(Event.COMPLETE, spritesCompleteHandler);
				_sprites.removeEventListener(Event.CHANGE, spritesChangeHandler);
				_sprites.removeEventListener(ProgressEvent.PROGRESS, spritesProgressHandler);
				_sprites.removeEventListener(ErrorEvent.ERROR, spritesErrorHandler);
				_sprites = null;
			}
			
			_things = new ThingTypeStorage();
			_things.addEventListener(Event.COMPLETE, thingsCompleteHandler);
			_things.addEventListener(Event.CHANGE, thingsChangeHandler);
			_things.addEventListener(ProgressEvent.PROGRESS, thingsProgressHandler);
			_things.addEventListener(ErrorEvent.ERROR, thingsErrorHandler);
			
			
			_sprites = new SpriteStorage();
			_sprites.addEventListener(Event.COMPLETE, spritesCompleteHandler);
			_sprites.addEventListener(Event.CHANGE, spritesChangeHandler);
			_sprites.addEventListener(ProgressEvent.PROGRESS, spritesProgressHandler);
			_sprites.addEventListener(ErrorEvent.ERROR, spritesErrorHandler);
			
			_things.sprites = _sprites;
			_things.load(_datFile, version);
		}
		
		private function onGetAssetsInfo(args:Array) : void
		{
			this.sendAssetsInfo();
		}
		
		private function onCompileAssets(args:Array) : void
		{
			var dat : File;
			var spr : File;
			var version : AssetsVersion;
			
			if (_things == null || !_things.loaded || !_sprites.loaded)
			{
				sendCommand(new ErrorCommand("Assets is not loaded."));
				return;
			}
			
			try
			{
				dat = new File(args[0]);
				spr = new File(args[1]);
				version = AssetsVersion.getVersionByValue(args[2]);
			} 
			catch(error:Error) 
			{
				sendError(error.message, error.getStackTrace(), error.errorID);
				return;
			}
			
			sendCommand(new Command(CommandType.SHOW_PROGRESS_BAR, "Compiling"));
			
			if (_things.compile(dat, version) && _sprites.compile(spr, version))
			{
				assetsCompileComplete();
			}
		}
		
		private function onNewThing(args:Array) : void
		{
			var category : String;
			var thing : ThingType;
			var message : String;
			
			category = ThingCategory.getCategory(args[0]);
			if (category != null)
			{
				thing = ThingUtils.createThing();
				if (_things.addThing(thing, category))
				{
					message = StringUtil.substitute("Added {0} id {1}.", category, thing.id);
					sendCommand(new MessageCommand(message, "Info"));
				}
			}
		}
		
		private function onGetThing(args:Array) : void
		{
			var id : uint;
			var category : String;
			var thing : ThingType;
			var spriteIndex : Vector.<uint>;
			var length : uint;
			var i :uint;
			var list : Array;
			
			list = [];
			
			id = args[0];
			category = ThingCategory.getCategory(args[1]);
			if (category == null)
			{
				sendError("Invalid thing category.");
				return;
			}
			
			thing = _things.getThingType(id,  category);
			if (thing == null)
			{
				sendError(StringUtil.substitute("{0} {1} not found.", StringUtil.capitaliseFirstLetter(category), id));
				return;
			}
			
			try
			{
				spriteIndex = thing.spriteIndex;
				length = spriteIndex.length;
				for (i = 0; i < length; i++)
				{
					list[i] = _sprites.getPixels(spriteIndex[i]);
				}
			} 
			catch(error:Error)
			{
				sendError(error.message, error.getStackTrace(), error.errorID);
				return;
			}
			
			sendCommand(new SetThingCommand(thing, list));
		}
		
		private function onChangeThing(args:Array) : void
		{
			var thing : ThingType;
			var message : String;
			
			thing = args[0] as ThingType;
			if (thing != null)
			{
				if (_things.replace(thing, thing.category, thing.id))
				{
					message = StringUtil.substitute("{0} {1} changed.", StringUtil.capitaliseFirstLetter(thing.category), thing.id);
					sendCommand(new MessageCommand(message, "Info"));
				}
			}
		}
		
		private function onExportThing(args:Array) : void
		{
			var id : uint;
			var category : String;
			var file : File;
			var version : AssetsVersion;
			var message : String;
			
			try
			{
				id = args[0];
				category = args[1];
				version = AssetsVersion.getVersionByValue(args[2]);
				file = new File(args[3]);
			} 
			catch(error:Error) 
			{
				sendError(error.message, error.getStackTrace(), error.errorID);
				return;
			}
			
			//trace(id, category, file.nativePath, version);
			/*if (_things.exportThing(thing, version, file))
			{
				message = StringUtil.substitute("{0} {1} export complete.", StringUtil.capitaliseFirstLetter(thing.category), thing.id);
				sendCommand(new ShowMessageCommand(message, "Info"));
			}*/
		}
		
		private function onDuplicateThing(args:Array) : void
		{
			var id : uint;
			var category : String;
			var thing : ThingType;
			var copy : ThingType;
			var message : String;
			
			id = args[0];
			category = args[1];
			thing = _things.getThingType(id, category);
			
			if (thing != null && ThingCategory.getCategory(category) != null)
			{
				copy = ThingUtils.copyThing(thing);
				if (copy != null && _things.addThing(copy, category))
				{
					message = StringUtil.substitute("Duplicated {0} {1} to {2}.", category, id, copy.id);
					sendCommand(new MessageCommand(message));
				}
			}
		}
		
		private function onGetSpriteList(args:Array) : void
		{
			this.sendSpriteList(args[0]);
		}
		
		private function onReplaceSprite(args:Array) : void
		{
			var id : uint;
			var pixels : ByteArray;
			
			try
			{
				id = args[0];
				pixels = args[1];
			} 
			catch(error:Error) 
			{
				sendError(error.message, error.getStackTrace(), error.errorID);
				return;
			}
			
			if (_sprites.replaceSprite(id, pixels))
			{
				sendCommand(new MessageCommand(StringUtil.substitute("Sprite id {0} replaced.", id), "Info"));
				this.sendSpriteList(id);
			}
		}
		
		private function onImportSprite(args:Array) : void
		{
			var pixels : ByteArray;
			
			try
			{
				pixels = args[0];
			} 
			catch(error:Error) 
			{
				sendError(error.message, error.getStackTrace(), error.errorID);
				return;
			}
			
			if (_sprites.addSprite(pixels))
			{
				sendCommand(new MessageCommand(StringUtil.substitute("Added new sprite id {0}.", _sprites.spritesCount), "Info"));
			}
		}
		
		private function assetsLoadComplete() : void
		{
			sendCommand(new Command(CommandType.HIDE_PROGRESS_BAR));
			sendCommand(new Command(CommandType.LOAD_COMPLETE));
			sendCommand(new MessageCommand("Load Complete.", "Info"));
		}
		
		private function assetsCompileComplete() : void
		{
			sendCommand(new Command(CommandType.HIDE_PROGRESS_BAR));
			sendCommand(new MessageCommand("Compile Complete.", "Info"));
		}
		
		public function sendAssetsInfo() : void
		{
			var info : AssetsInfo;
			
			if (_things == null  || _sprites == null)
			{
				return;
			}
			
			info = new AssetsInfo();
			info.version = _version.value;
			info.datSignature = _things.signature;
			info.minItemId = ThingTypeStorage.MIN_ITEM_ID;
			info.maxItemId = _things.itemsCount;
			info.minOutfitId = ThingTypeStorage.MIN_OUTFIT_ID;
			info.maxOutfitId = _things.outfitsCount;
			info.minEffectId = ThingTypeStorage.MIN_EFFECT_ID;
			info.maxEffectId = _things.effectsCount;
			info.minMissileId = ThingTypeStorage.MIN_MISSILE_ID;
			info.maxMissileId = _things.missilesCount;
			info.sprSignature = _sprites.signature;
			info.minSpriteId = 0;
			info.maxSpriteId = _sprites.spritesCount;
			
			sendCommand(new SetAssetsInfoCommand(info));
		}
		
		private function sendSpriteList(target:uint) : void
		{
			var min : uint;
			var max : uint
			var list : Array;
			var i : int;
			var pixels : ByteArray;
			
			if (!_sprites.loaded)
			{
				return;
			}
			
			min = Math.max(0, target - 50);
			max = min == 0 ? Math.min(_sprites.spritesCount, target + 100) : Math.min(_sprites.spritesCount, target + 50);
			min = max == _sprites.spritesCount ? Math.max(0, min - 50) : min;
			list = [];
			
			for (i = min; i <= max; i++)
			{
				pixels = _sprites.getPixels(i);
				if (pixels != null)
				{
					list[i] = pixels;
				}
			}
			
			sendCommand(new SetSpriteListCommand(target, min, max, list));
		}
		
		private function sendError(message:String, stack:String = "", id:uint = 0) : void
		{
			if (!StringUtil.isEmptyOrNull(message))
			{
				sendCommand(new ErrorCommand(message, stack, id));
			}
		}
		
		//--------------------------------------
		// Event Handlers
		//--------------------------------------
		
		protected function thingsCompleteHandler(event:Event) : void
		{
			if (_sprites != null && !_sprites.loaded)
			{
				_sprites.load(_sprFile, _version);
			}
		}
		
		protected function thingsChangeHandler(event:Event) : void
		{
			sendAssetsInfo();
		}
		
		protected function thingsProgressHandler(event:ProgressEvent) : void
		{
			sendProgress(1, event.bytesLoaded, event.bytesTotal);
		}
		
		protected function thingsErrorHandler(event:ErrorEvent) : void
		{
			sendError(event.text, "", event.errorID);
		}	
		
		protected function spritesCompleteHandler(event:Event) : void
		{
			if (_things != null && _things.loaded)
			{
				this.assetsLoadComplete();
			}
		}
		
		protected function spritesChangeHandler(event:Event) : void
		{
			sendAssetsInfo();
		}
		
		protected function spritesProgressHandler(event:ProgressEvent) : void
		{
			sendProgress(2, event.bytesLoaded, event.bytesTotal);
		}
		
		protected function spritesErrorHandler(event:ErrorEvent) : void
		{
			sendError(event.text, "", event.errorID);
		}
	}
}
