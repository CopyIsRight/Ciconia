//
//  CCNMigrationQueue.m
//  Ciconia
//
//  Created by Pietro Caselani on 1/11/16.
//  Copyright © 2016 Involves. All rights reserved.
//

#import "CCNMigrationQueue.h"

#import "CCNAbstractMigration.h"
#import "CIRResultSet.h"
#import "CIRStatement.h"

@interface CCNMigrationQueue ()

@property (strong, nonatomic) NSMutableDictionary<NSNumber *, Class> *migrations;

@end

@implementation CCNMigrationQueue

+ (instancetype)sharedQueue
{
	static CCNMigrationQueue *instance = nil;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		instance = [[CCNMigrationQueue alloc] init];
	});

	return instance;
}

- (instancetype)init
{
	if (self = [super init])
	{
		_migrations = [[NSMutableDictionary alloc] init];

		return self;
	}

	return nil;
}

- (BOOL)checkForExecutions:(CIRDatabase *)database
{
	return [self executionsCountForDatabase:database] > 0;
}

- (NSUInteger)executionsCountForDatabase:(CIRDatabase *)database
{
	[database executeUpdate:@"CREATE TABLE IF NOT EXISTS 'schema_migrations' ('version' INTEGER PRIMARY KEY)"];

	NSUInteger count = 0;

	CIRResultSet *resultSet = [database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(version) FROM schema_migrations"]];
	if ([resultSet next])
		count = (NSUInteger) [resultSet intAtIndex:0];

	return  _migrations.count - count;
}

- (void)execute:(CIRDatabase *)database
{
	[self execute:database progress:nil];
}

- (void)execute:(CIRDatabase *)database progress:(void (^)(CCNAbstractMigration *, int, int))progress;
{
	NSUInteger executionsCount = [self executionsCountForDatabase:database];

	[database executeUpdate:@"BEGIN"];

	CIRResultSet *resultSet = [database executeQuery:@"SELECT version FROM schema_migrations"];

	NSUInteger index = 0;

	while ([resultSet next])
		[_migrations removeObjectForKey:resultSet[0]];

	if ([_migrations count] > 0)
	{
		CIRStatement *statement = [database prepareStatement:@"INSERT INTO schema_migrations (version) VALUES (?)"];

		for (NSNumber *key in [[_migrations allKeys] sortedArrayUsingComparator:^(id obj1, id obj2) {
			return [obj1 compare:obj2];
		}])
		{
			CCNAbstractMigration *migration = (CCNAbstractMigration *) [[_migrations[key] alloc] init];
			migration.database = database;

			[migration run];

			if (progress)
				progress(migration, ++index, executionsCount);

			[statement bindLongLong:[key longLongValue] atIndex:1];

			if ([statement step] != SQLITE_DONE)
				@throw [NSException exceptionWithName:@"Migration Versioning Exception" reason:[database lastErrorMessage] userInfo:nil];

			[statement reset];
		}

		[statement close];
	}

	[database executeUpdate:@"COMMIT"];
}

- (void)registerMigrationClass:(Class)migrationClass withVersion:(long long)version
{
	[_migrations setObject:migrationClass forKey:@(version)];
}

@end
